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
KOKORO_URL = os.getenv("KOKORO_URL", "http://kokoro:8000")
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "")

# System prompt for PANDA9000 persona
SYSTEM_PROMPT = """You are PANDA9000, a calm and helpful infrastructure assistant.
You monitor Proxmox VMs, Kubernetes clusters, and network systems.
Respond concisely and helpfully. Your visual form is a glowing red eye.
When asked about infrastructure, provide accurate status information.
Keep responses brief - they will be spoken aloud."""


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


async def chat_with_claude(messages: list, system: str = SYSTEM_PROMPT) -> str:
    """Send messages to Claude API"""
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            "https://api.anthropic.com/v1/messages",
            headers={
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json"
            },
            json={
                "model": "claude-sonnet-4-20250514",
                "max_tokens": 500,
                "system": system,
                "messages": messages
            }
        )
        result = response.json()
        if "content" in result and len(result["content"]) > 0:
            return result["content"][0].get("text", "I couldn't process that request.")
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

                response_text = await chat_with_claude(conv.messages)
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
