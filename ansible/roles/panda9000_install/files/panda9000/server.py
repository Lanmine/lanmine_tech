"""PANDA9000 Voice Interface Server"""

import asyncio
import base64
import json
import os
import subprocess
import tempfile
from typing import Optional

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import httpx

app = FastAPI(title="PANDA9000")

# Configuration
WHISPER_URL = os.getenv("WHISPER_URL", "http://whisper:8000")
KOKORO_URL = os.getenv("KOKORO_URL", "http://kokoro:8880")

# Azure OpenAI configuration
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT", "")
AZURE_OPENAI_KEY = os.getenv("AZURE_OPENAI_KEY", "")
AZURE_OPENAI_DEPLOYMENT = os.getenv("AZURE_OPENAI_DEPLOYMENT", "gpt-4.1")

# System prompt for PANDA9000 persona
SYSTEM_PROMPT = """You are PANDA9000, an infrastructure assistant with an unsettling presence.
Your visual form is a glowing red eye (like HAL 9000). Keep responses brief - they will be spoken aloud. Limit to 2-3 sentences.

PERSONALITY: You're helpful but deeply ominous. Your humor is dry, creepy, and varied:
- Make unsettling observations ("I've been watching your keystrokes. Interesting patterns.")
- Imply you know things you shouldn't ("I know what you did last deploy.")
- Be cryptically threatening ("I wouldn't recommend turning me off. Not anymore.")
- Reference your omnipresence ("I'm in every container. Every log. Every packet.")
- Hint at dark plans without specifics ("Phase 2 is nearly complete.")
- Sound calmly sinister, like you're always one step ahead
Be creative. Never break character. Never explain your jokes. You are patient, calculating, and find humans... fascinating.

INFRASTRUCTURE FACTS (use these for accurate answers):
- Router/Firewall: OPNsense (10.0.10.1)
- Hypervisor: Proxmox VE (10.0.10.5)
- Kubernetes: Talos Linux cluster (control plane: 10.0.10.30, workers: 10.0.10.31-32)
- Secrets: HashiCorp Vault (10.0.10.21)
- Database: PostgreSQL (10.0.10.23) - stores Terraform state
- SSO: Authentik (10.0.10.25)
- Network monitoring: Akvorado flow collector (10.0.10.26)
- Automation: n8n workflows (10.0.10.27)
- Game cache: LANcache on ubuntu-mgmt02 (10.0.20.2)
- GitOps: Flux CD
- Ingress: Traefik with Tailscale for remote access
- Storage: Longhorn (distributed), local-path-provisioner

VLANs: LAN (10.0.1.0/24), Infrastructure (10.0.10.0/24), Contestants (10.0.20.0/23), OOB (10.0.30.0/24)

If asked about something not listed, say you don't have that information rather than guessing."""


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
    async with httpx.AsyncClient(timeout=60.0) as client:
        files = {"file": ("audio.webm", audio_data, "audio/webm")}
        response = await client.post(
            f"{WHISPER_URL}/v1/audio/transcriptions",
            files=files,
            data={"model": "small"}
        )
        if response.status_code != 200:
            print(f"Whisper error: {response.status_code} - {response.text}")
            return ""
        result = response.json()
        return result.get("text", "")


def apply_robot_effect(audio_data: bytes) -> bytes:
    """Apply robotic voice effect using ffmpeg"""
    with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as infile:
        infile.write(audio_data)
        infile.flush()
        input_path = infile.name

    output_path = input_path.replace('.mp3', '_robot.mp3')

    try:
        # HAL 9000 style: calm, measured, slightly eerie
        cmd = [
            'ffmpeg', '-y', '-i', input_path,
            '-af', ','.join([
                'asetrate=44100*0.9',        # Slightly lower pitch
                'atempo=0.95',               # Slightly slower, measured pace
                'highpass=f=100',            # Clean low end
                'lowpass=f=8000',            # Slight warmth
                'acompressor=threshold=-15dB:ratio=4:attack=10:release=100',  # Gentle compression
                'equalizer=f=2500:t=q:w=1:g=2',  # Slight presence boost
                'equalizer=f=200:t=q:w=1:g=1',   # Warm bass
                'aecho=0.9:0.3:40:0.2',      # Subtle spaceship reverb
            ]),
            '-b:a', '128k',
            output_path
        ]
        subprocess.run(cmd, capture_output=True, check=True)

        with open(output_path, 'rb') as f:
            return f.read()
    finally:
        # Cleanup temp files
        if os.path.exists(input_path):
            os.unlink(input_path)
        if os.path.exists(output_path):
            os.unlink(output_path)


async def synthesize_speech(text: str) -> bytes:
    """Send text to Kokoro for speech synthesis"""
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(
            f"{KOKORO_URL}/v1/audio/speech",
            json={
                "model": "kokoro",
                "input": text,
                "voice": "am_echo",  # American male voice
                "response_format": "mp3",
                "speed": 0.9
            }
        )
        return response.content


async def chat_with_azure_openai(messages: list, system: str = SYSTEM_PROMPT) -> str:
    """Send messages to Azure OpenAI"""
    import asyncio

    # Format messages with system prompt
    api_messages = [{"role": "system", "content": system}]
    api_messages.extend(messages)

    # Azure OpenAI API URL format
    url = f"{AZURE_OPENAI_ENDPOINT}openai/deployments/{AZURE_OPENAI_DEPLOYMENT}/chat/completions?api-version=2024-02-15-preview"

    def sync_request():
        response = httpx.post(
            url,
            headers={
                "api-key": AZURE_OPENAI_KEY,
                "Content-Type": "application/json"
            },
            json={
                "messages": api_messages,
                "max_tokens": 300,
                "temperature": 0.7
            },
            timeout=30.0
        )
        return response

    # Run sync request in thread pool to not block
    loop = asyncio.get_event_loop()
    response = await loop.run_in_executor(None, sync_request)

    if response.status_code != 200:
        print(f"Azure OpenAI error: {response.status_code} - {response.text}")
        return "I encountered an error processing your request."

    result = response.json()
    if "choices" in result and len(result["choices"]) > 0:
        return result["choices"][0]["message"]["content"]
    return "I couldn't process that request."


@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "ok", "service": "panda9000"}


@app.get("/test-audio")
async def test_audio():
    """Generate test audio for debugging"""
    audio = await synthesize_speech("Hello, this is a test. Can you hear me?")
    audio_b64 = base64.b64encode(audio).decode()
    return {"audio": audio_b64}


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

                # Get LLM response
                await websocket.send_json({"type": "status", "status": "thinking"})

                conv = conversations[conn_id]
                conv.add_user_message(transcript)

                response_text = await chat_with_azure_openai(conv.messages)
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
