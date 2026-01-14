"""PANDA9000 Voice Interface Server"""

import asyncio
import base64
import json
import os
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import httpx

app = FastAPI(title="PANDA9000")

# Configuration
WHISPER_URL = os.getenv("WHISPER_URL", "http://whisper:8000")
KOKORO_URL = os.getenv("KOKORO_URL", "http://kokoro:8880")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://ollama:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "phi3:mini")

# System prompt for PANDA9000 persona
SYSTEM_PROMPT = """You are PANDA9000, a calm and helpful infrastructure assistant.
You monitor Proxmox VMs, Kubernetes clusters, and network systems.
Respond concisely and helpfully. Your visual form is a glowing red eye.
When asked about infrastructure, provide accurate status information.
Keep responses brief - they will be spoken aloud. Limit responses to 2-3 sentences."""


class ConversationState:
    """Manages conversation context for live sessions"""
    def __init__(self):
        self.messages = []
        self.active = False

    def add_user_message(self, content: str):
        self.messages.append({"role": "user", "content": content})

    def add_assistant_message(self, content: str):
        self.messages.append({"role": "assistant", "content": content})

    def clear(self):
        self.messages = []
        self.active = False


# Store conversations per websocket connection
conversations: dict[int, ConversationState] = {}


async def transcribe_audio(audio_data: bytes) -> str:
    """Send audio to Whisper for transcription"""
    async with httpx.AsyncClient(timeout=30.0) as client:
        files = {"file": ("audio.webm", audio_data, "audio/webm")}
        response = await client.post(
            f"{WHISPER_URL}/v1/audio/transcriptions",
            files=files,
            data={"model": "whisper-small"}
        )
        result = response.json()
        return result.get("text", "")


async def synthesize_speech(text: str) -> bytes:
    """Send text to Kokoro for speech synthesis"""
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            f"{KOKORO_URL}/v1/audio/speech",
            json={
                "model": "kokoro",
                "input": text,
                "voice": "af_sarah",  # Natural female voice
                "response_format": "mp3"
            }
        )
        return response.content


async def chat_with_ollama(messages: list, system: str = SYSTEM_PROMPT) -> str:
    """Send messages to Ollama (local LLM)"""
    # Format messages for Ollama chat API
    ollama_messages = [{"role": "system", "content": system}]
    ollama_messages.extend(messages)

    async with httpx.AsyncClient(timeout=120.0) as client:
        response = await client.post(
            f"{OLLAMA_URL}/api/chat",
            json={
                "model": OLLAMA_MODEL,
                "messages": ollama_messages,
                "stream": False
            }
        )
        result = response.json()
        if "message" in result:
            return result["message"].get("content", "I couldn't process that request.")
        return "I encountered an error processing your request."


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "ok", "service": "panda9000"}


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for voice communication"""
    await websocket.accept()
    conn_id = id(websocket)
    conversations[conn_id] = ConversationState()

    try:
        while True:
            data = await websocket.receive_json()
            action = data.get("action")

            if action == "start_session":
                conversations[conn_id].active = True
                conversations[conn_id].clear()
                await websocket.send_json({"type": "session_started"})

            elif action == "end_session":
                conversations[conn_id].active = False
                conversations[conn_id].clear()
                await websocket.send_json({"type": "session_ended"})

            elif action == "audio":
                # Decode base64 audio
                audio_b64 = data.get("audio", "")
                audio_data = base64.b64decode(audio_b64)

                # Transcribe
                await websocket.send_json({"type": "status", "status": "transcribing"})
                transcript = await transcribe_audio(audio_data)
                await websocket.send_json({"type": "transcript", "text": transcript})

                if not transcript.strip():
                    await websocket.send_json({"type": "status", "status": "idle"})
                    continue

                # Check for end session phrase
                if conversations[conn_id].active and "goodbye" in transcript.lower():
                    conversations[conn_id].active = False
                    conversations[conn_id].clear()
                    response_text = "Goodbye. Ending our session."
                    await websocket.send_json({"type": "response", "text": response_text})

                    # Synthesize goodbye
                    await websocket.send_json({"type": "status", "status": "speaking"})
                    audio = await synthesize_speech(response_text)
                    audio_b64 = base64.b64encode(audio).decode()
                    await websocket.send_json({"type": "audio", "audio": audio_b64})
                    await websocket.send_json({"type": "session_ended"})
                    continue

                # Get Claude response
                await websocket.send_json({"type": "status", "status": "thinking"})

                conv = conversations[conn_id]
                conv.add_user_message(transcript)

                response_text = await chat_with_ollama(conv.messages)
                conv.add_assistant_message(response_text)

                await websocket.send_json({"type": "response", "text": response_text})

                # Synthesize speech
                await websocket.send_json({"type": "status", "status": "speaking"})
                audio = await synthesize_speech(response_text)
                audio_b64 = base64.b64encode(audio).decode()
                await websocket.send_json({"type": "audio", "audio": audio_b64})

                # If in live session, signal ready for next input
                if conv.active:
                    await websocket.send_json({"type": "status", "status": "listening"})
                else:
                    # Single query mode - clear after response
                    conv.clear()
                    await websocket.send_json({"type": "status", "status": "idle"})

    except WebSocketDisconnect:
        if conn_id in conversations:
            del conversations[conn_id]


# Serve static files
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.get("/")
async def root():
    """Serve the main page"""
    return FileResponse("static/index.html")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
