// PANDA9000 Voice Interface

class PANDA9000 {
    constructor() {
        this.ws = null;
        this.mediaRecorder = null;
        this.audioChunks = [];
        this.isRecording = false;
        this.isSessionActive = false;
        this.audioElement = null;
        this.audioQueue = [];
        this.isPlayingAudio = false;

        // DOM elements
        this.eye = document.getElementById('eye');
        this.status = document.getElementById('status');
        this.talkBtn = document.getElementById('talkBtn');
        this.transcript = document.getElementById('transcript');
        this.fullscreenBtn = document.getElementById('fullscreenBtn');

        this.init();
    }

    init() {
        this.connectWebSocket();
        this.setupEventListeners();
        this.initAudio();
    }

    initAudio() {
        // Create persistent audio element for reuse
        this.audioElement = new Audio();
        this.audioElement.playsInline = true;
        this.audioUnlocked = false;

        // Check if iOS/Safari
        const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
        const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
        const overlay = document.getElementById('audioOverlay');

        if (isIOS || isSafari) {
            if (overlay) {
                overlay.style.display = 'flex';
            }
        }

        // Unlock audio on tap - play silent sound to enable future playback
        const unlockAudio = async () => {
            if (this.audioUnlocked) {
                if (overlay) overlay.style.display = 'none';
                return;
            }

            try {
                // Play a tiny silent mp3 to unlock
                this.audioElement.src = 'data:audio/mp3;base64,SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA//tQxAAAAAANIAAAAAExBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV';
                await this.audioElement.play();
                this.audioUnlocked = true;
                console.log('Audio unlocked for iOS');
            } catch (e) {
                console.log('Audio unlock error:', e);
            }

            if (overlay) {
                overlay.style.display = 'none';
            }
        };

        if (overlay) {
            overlay.addEventListener('click', unlockAudio);
            overlay.addEventListener('touchend', unlockAudio);
        }

        // Also unlock on talk button press
        document.addEventListener('touchstart', unlockAudio, { once: true });
        document.addEventListener('click', unlockAudio, { once: true });
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

        // Test audio button
        const testBtn = document.getElementById('testAudioBtn');
        if (testBtn) {
            testBtn.addEventListener('click', () => this.testAudio());
        }
    }

    async testAudio() {
        this.addToTranscript('system', 'Testing audio...');

        try {
            // Request test audio from server
            const response = await fetch('/test-audio');
            if (!response.ok) {
                throw new Error('Failed to get test audio: ' + response.status);
            }

            const data = await response.json();
            this.addToTranscript('system', 'Got audio, size: ' + data.audio.length);

            // Try to play it immediately (within user gesture)
            const binaryString = atob(data.audio);
            const bytes = new Uint8Array(binaryString.length);
            for (let i = 0; i < binaryString.length; i++) {
                bytes[i] = binaryString.charCodeAt(i);
            }
            const blob = new Blob([bytes], { type: 'audio/mpeg' });
            const blobUrl = URL.createObjectURL(blob);

            // Create fresh audio element within gesture
            const testAudio = new Audio();
            testAudio.playsInline = true;
            testAudio.src = blobUrl;

            testAudio.onended = () => {
                this.addToTranscript('system', 'Test audio finished');
                URL.revokeObjectURL(blobUrl);
            };

            testAudio.onerror = (e) => {
                this.addToTranscript('system', 'Test audio error: ' + (testAudio.error?.message || 'unknown'));
            };

            await testAudio.play();
            this.addToTranscript('system', 'Test audio playing!');

        } catch (error) {
            this.addToTranscript('system', 'Test error: ' + error.message);
            console.error('Test audio error:', error);
        }
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
                // Ignore server's "speaking" status - we set it when audio actually plays
                if (data.status === 'speaking') {
                    break;
                }
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
                // Store response text, show after audio finishes
                this.pendingResponse = data.text;
                break;

            case 'audio':
                // Set speaking state when audio actually arrives
                this.setStatus('SPEAKING');
                this.setEyeState('speaking');
                this.playAudio(data.audio, this.pendingResponse);
                this.pendingResponse = null;
                break;

            case 'session_started':
                this.isSessionActive = true;
                this.eye.classList.add('session-active');
                break;

            case 'session_ended':
                this.isSessionActive = false;
                this.eye.classList.remove('session-active');
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

    async playAudio(base64Audio, responseText) {
        try {
            // Convert base64 to blob
            const binaryString = atob(base64Audio);
            const bytes = new Uint8Array(binaryString.length);
            for (let i = 0; i < binaryString.length; i++) {
                bytes[i] = binaryString.charCodeAt(i);
            }
            const blob = new Blob([bytes], { type: 'audio/mpeg' });
            const blobUrl = URL.createObjectURL(blob);

            // Use the persistent unlocked audio element for iOS compatibility
            const audio = this.audioElement;
            audio.src = blobUrl;

            // Store current blobUrl for cleanup
            const currentBlobUrl = blobUrl;

            audio.onended = () => {
                URL.revokeObjectURL(currentBlobUrl);
                // Show response text after audio finishes
                if (responseText) {
                    this.addToTranscript('assistant', responseText);
                }
                if (!this.isSessionActive) {
                    this.setStatus('IDLE');
                    this.setEyeState('idle');
                }
            };

            audio.onerror = (e) => {
                console.error('Audio error:', audio.error?.message);
                URL.revokeObjectURL(currentBlobUrl);
                // Still show text on error
                if (responseText) {
                    this.addToTranscript('assistant', responseText);
                }
                this.setStatus('IDLE');
                this.setEyeState('idle');
            };

            await audio.play();
        } catch (error) {
            console.error('Error playing audio:', error);
            // Still show text on error
            if (responseText) {
                this.addToTranscript('assistant', responseText);
            }
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
