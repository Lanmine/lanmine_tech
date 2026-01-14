// PANDA9000 Voice Interface

class PANDA9000 {
    constructor() {
        this.ws = null;
        this.mediaRecorder = null;
        this.audioChunks = [];
        this.isRecording = false;
        this.isSessionActive = false;
        this.audioContext = null;

        // DOM elements
        this.eye = document.getElementById('eye');
        this.status = document.getElementById('status');
        this.talkBtn = document.getElementById('talkBtn');
        this.sessionBtn = document.getElementById('sessionBtn');
        this.transcript = document.getElementById('transcript');
        this.fullscreenBtn = document.getElementById('fullscreenBtn');

        this.init();
    }

    init() {
        this.connectWebSocket();
        this.setupEventListeners();
        this.initAudioContext();
    }

    connectWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        this.ws = new WebSocket(`${protocol}//${window.location.host}/ws`);

        this.ws.onopen = () => {
            console.log('Connected to PANDA9000');
            this.setStatus('IDLE');
        };

        this.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleMessage(data);
        };

        this.ws.onclose = () => {
            console.log('Disconnected from PANDA9000');
            this.setStatus('DISCONNECTED');
            // Reconnect after 3 seconds
            setTimeout(() => this.connectWebSocket(), 3000);
        };

        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }

    setupEventListeners() {
        // Talk button (push-to-talk)
        this.talkBtn.addEventListener('mousedown', () => this.startRecording());
        this.talkBtn.addEventListener('mouseup', () => this.stopRecording());
        this.talkBtn.addEventListener('touchstart', (e) => {
            e.preventDefault();
            this.startRecording();
        });
        this.talkBtn.addEventListener('touchend', (e) => {
            e.preventDefault();
            this.stopRecording();
        });

        // Session button
        this.sessionBtn.addEventListener('click', () => this.toggleSession());

        // Fullscreen button
        this.fullscreenBtn.addEventListener('click', () => this.toggleFullscreen());

        // Keyboard shortcut (spacebar for talk)
        document.addEventListener('keydown', (e) => {
            if (e.code === 'Space' && !e.repeat && !this.isRecording) {
                e.preventDefault();
                this.startRecording();
            }
        });

        document.addEventListener('keyup', (e) => {
            if (e.code === 'Space' && this.isRecording) {
                e.preventDefault();
                this.stopRecording();
            }
        });
    }

    initAudioContext() {
        this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }

    async startRecording() {
        if (this.isRecording) return;

        try {
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            this.mediaRecorder = new MediaRecorder(stream, { mimeType: 'audio/webm' });
            this.audioChunks = [];

            this.mediaRecorder.ondataavailable = (event) => {
                this.audioChunks.push(event.data);
            };

            this.mediaRecorder.onstop = () => {
                const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
                this.sendAudio(audioBlob);
                stream.getTracks().forEach(track => track.stop());
            };

            this.mediaRecorder.start();
            this.isRecording = true;
            this.talkBtn.classList.add('recording');
            this.setStatus('LISTENING');
            this.setEyeState('listening');
        } catch (error) {
            console.error('Error accessing microphone:', error);
            this.addToTranscript('system', 'Error: Could not access microphone');
        }
    }

    stopRecording() {
        if (!this.isRecording || !this.mediaRecorder) return;

        this.mediaRecorder.stop();
        this.isRecording = false;
        this.talkBtn.classList.remove('recording');
    }

    async sendAudio(audioBlob) {
        const reader = new FileReader();
        reader.onloadend = () => {
            const base64 = reader.result.split(',')[1];
            this.ws.send(JSON.stringify({
                action: 'audio',
                audio: base64
            }));
        };
        reader.readAsDataURL(audioBlob);
    }

    toggleSession() {
        if (this.isSessionActive) {
            this.ws.send(JSON.stringify({ action: 'end_session' }));
        } else {
            this.ws.send(JSON.stringify({ action: 'start_session' }));
        }
    }

    handleMessage(data) {
        switch (data.type) {
            case 'status':
                this.setStatus(data.status.toUpperCase());
                this.setEyeState(data.status);
                if (data.status === 'listening' && this.isSessionActive) {
                    // Auto-start recording in live session
                    setTimeout(() => this.startRecording(), 500);
                }
                break;

            case 'transcript':
                this.addToTranscript('user', data.text);
                break;

            case 'response':
                this.addToTranscript('assistant', data.text);
                break;

            case 'audio':
                this.playAudio(data.audio);
                break;

            case 'session_started':
                this.isSessionActive = true;
                this.sessionBtn.classList.add('active');
                this.sessionBtn.innerHTML = '<span class="btn-icon">&#128721;</span> End Session';
                this.eye.classList.add('session-active');
                this.addToTranscript('system', 'Live session started');
                break;

            case 'session_ended':
                this.isSessionActive = false;
                this.sessionBtn.classList.remove('active');
                this.sessionBtn.innerHTML = '<span class="btn-icon">&#128172;</span> Live Session';
                this.eye.classList.remove('session-active');
                this.addToTranscript('system', 'Session ended');
                this.setStatus('IDLE');
                this.setEyeState('idle');
                break;
        }
    }

    setStatus(text) {
        this.status.textContent = text;
    }

    setEyeState(state) {
        this.eye.classList.remove('listening', 'thinking', 'speaking');
        if (state !== 'idle') {
            this.eye.classList.add(state);
        }
    }

    addToTranscript(role, text) {
        const timestamp = new Date().toLocaleTimeString();
        const entry = document.createElement('div');
        entry.className = role;

        if (role === 'user') {
            entry.innerHTML = `<span class="timestamp">[${timestamp}]</span> You: ${text}`;
        } else if (role === 'assistant') {
            entry.innerHTML = `<span class="timestamp">[${timestamp}]</span> PANDA: ${text}`;
        } else {
            entry.innerHTML = `<span class="timestamp">[${timestamp}]</span> <em>${text}</em>`;
            entry.style.color = '#666';
        }

        this.transcript.appendChild(entry);
        this.transcript.scrollTop = this.transcript.scrollHeight;
    }

    async playAudio(base64Audio) {
        try {
            // Use Audio element for more reliable playback
            const audio = new Audio(`data:audio/mp3;base64,${base64Audio}`);

            audio.onended = () => {
                if (!this.isSessionActive) {
                    this.setStatus('IDLE');
                    this.setEyeState('idle');
                }
            };

            audio.onerror = (e) => {
                console.error('Audio playback error:', e);
                this.setStatus('IDLE');
                this.setEyeState('idle');
            };

            await audio.play();
        } catch (error) {
            console.error('Error playing audio:', error);
            this.setStatus('IDLE');
            this.setEyeState('idle');
        }
    }

    toggleFullscreen() {
        if (!document.fullscreenElement) {
            document.documentElement.requestFullscreen();
        } else {
            document.exitFullscreen();
        }
    }
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.panda = new PANDA9000();
});
