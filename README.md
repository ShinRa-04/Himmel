# Himmel

**AI-powered SMS chatbot** — send a text message from one Android phone, get an AI-generated response back via SMS, powered by a local Ollama LLM.

## Architecture

```
┌──────────────┐   SMS    ┌──────────────┐   ADB/USB   ┌──────────────────┐   HTTP    ┌────────┐
│  Sender App  │ ──────► │  Server App  │ ──────────► │  Python Backend  │ ────────► │ Ollama │
│  (Phone A)   │ ◄────── │  (Phone B)   │ ◄────────── │   (PC/FastAPI)   │ ◄──────── │  LLM   │
└──────────────┘   SMS    └──────────────┘   ADB Intent └──────────────────┘   HTTP    └────────┘
```

| Component | Tech | Description |
|-----------|------|-------------|
| **sender_app** | Flutter / Dart | Chat UI on Phone A. Sends user messages as chunked SMS, reassembles AI responses. |
| **server_app** | Flutter / Dart | Relay on Phone B. Receives SMS chunks, queues them to disk, sends back AI responses as SMS. |
| **backend** | Python / FastAPI | Runs on PC connected to Phone B via USB. Pulls chunks via ADB, sends to Ollama, pushes response back. |

### SMS Chunking Protocol

Messages exceeding 160 characters are split with metadata headers:

```
ID:<md5_hash>
M:<total_chunks>      (chunk 1 only)
I:<chunk_index>
T:<payload>
```

## Prerequisites

- **Python 3.11+**
- **Flutter SDK** (Dart ^3.10.7)
- **Ollama** with a model pulled (default: `gemma3:4b`)
- **Android SDK / ADB** on PATH
- **Two Android phones** — one as sender, one as server relay
- USB cable connecting Phone B to the PC

## Setup

### 1. Clone & Configure

```bash
git clone https://github.com/ShinRa-04/Himmel.git
cd Himmel
cp .env.example .env
# Edit .env — set your device ID, phone numbers, and Ollama model
```

### 2. Backend (Python)

```bash
cd backend
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS/Linux
pip install -r requirements.txt
```

### 3. Flutter Apps

```bash
# Sender App (Phone A)
cd sender_app
flutter pub get
flutter run

# Server App (Phone B)
cd server_app
flutter pub get
flutter run
```

### 4. Ollama

```bash
ollama pull gemma3:4b
ollama serve
```

## Running

**Start the backend server:**

```bash
cd backend
uvicorn main:app --host 127.0.0.1 --port 8000
```

**Start the ADB bridge** (in a separate terminal):

```bash
cd backend
python adb_bridge.py
```

> The ADB bridge polls Phone B for incoming SMS chunks, forwards them to the FastAPI server, and pushes AI responses back to Phone B via ADB intents.

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/chunk` | Receive an SMS chunk |
| `POST` | `/api/process` | Process a complete message directly |
| `GET` | `/api/result/{hash}` | Poll for AI response by message hash |
| `GET` | `/api/buffer/status` | Debug: view chunk buffer state |

## Configuration

All settings are in `.env` — see [.env.example](.env.example) for the full list:

| Variable | Description |
|----------|-------------|
| `SERVER_DEVICE_ID` | ADB device ID of Phone B (`adb devices`) |
| `TARGET_PHONE_NUMBER` | Phone number of Phone A |
| `OLLAMA_MODEL` | LLM model name (e.g. `gemma3:4b`) |
| `SERVER_HOST` / `SERVER_PORT` | FastAPI bind address |
| `MAX_SMS_LENGTH` | Chunk size limit (default: 160) |

## Project Structure

```
Himmel/
├── backend/
│   ├── main.py                  # FastAPI server
│   ├── adb_bridge.py            # ADB polling & intent bridge
│   ├── models.py                # Pydantic request models
│   ├── requirements.txt
│   └── services/
│       ├── chunk_calculator.py  # SMS chunking logic
│       ├── mobile_monitor.py    # Notification-based SMS monitor
│       ├── ollama_service.py    # Ollama LLM client
│       └── trigger_response.py  # Response trigger via monitor
├── sender_app/                  # Flutter — Phone A chat UI
│   └── lib/
│       ├── main.dart
│       ├── models/              # Message model
│       ├── screens/             # Chat screen
│       ├── services/            # SMS, chunking, settings
│       ├── theme/               # App theme & colors
│       └── widgets/             # Chat UI components
├── server_app/                  # Flutter — Phone B relay
│   └── lib/
│       ├── main.dart
│       ├── models/              # Pending message model
│       └── services/            # SMS queue, chunking, forwarding
├── .env.example                 # Environment template
├── .gitattributes
└── .gitignore
```

## License

This project is provided as-is for personal and educational use.
