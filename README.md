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
| **server_app** | Flutter / Dart | Relay on Phone B. Receives SMS chunks, queues them to disk, sends back AI responses as SMS. Must be set as the **default SMS app** on the device. |
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
- **Android SDK / ADB** on your system PATH
- **Two Android phones** — one as sender (Phone A), one as server relay (Phone B)
- **USB cable** connecting Phone B to the PC
- **USB Debugging** enabled on Phone B (Settings → Developer Options → USB Debugging)

## Setup

### 1. Clone & Configure

```bash
git clone https://github.com/ShinRa-04/Himmel.git
cd Himmel
cp .env.example .env
```

Edit `.env` and fill in your values:

```dotenv
SERVER_DEVICE_ID=<your device id>       # run `adb devices` to find this
TARGET_PHONE_NUMBER=<phone A number>    # the sender phone's number
OLLAMA_MODEL=gemma3:4b                  # or any model you've pulled
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

> **Note on Flutter project files:** This repository only contains the source code and essential project configuration. Flutter-generated files (`.dart_tool/`, `.flutter-plugins`, `GeneratedPluginRegistrant`, platform `build/` directories, etc.) are excluded via `.gitignore`. After cloning, you **must** run `flutter pub get` inside each app directory to regenerate these files before building or running.

```bash
# Sender App (install on Phone A)
cd sender_app
flutter pub get
flutter run

# Server App (install on Phone B)
cd server_app
flutter pub get
flutter run
```

After installing `server_app` on Phone B, go to **Settings → Apps → Default apps → SMS app** and set it to **Himmel Server**. This is required because Android only delivers `SMS_DELIVER` intents to the default SMS app.

### 4. Ollama

Install [Ollama](https://ollama.com) and pull a model:

```bash
ollama pull gemma3:4b
ollama serve
```

## Running

You need **three terminals** running simultaneously:

### Terminal 1 — FastAPI Backend Server

```bash
cd backend
uvicorn main:app --host 127.0.0.1 --port 8000
```

### Terminal 2 — ADB Bridge

The ADB bridge is the critical link between Phone B and the backend. It:
1. Polls the server phone's app-private file queue via `adb shell run-as`
2. Reads new SMS chunk JSON files and forwards them to the FastAPI `/api/chunk` endpoint
3. Polls `/api/result/{hash}` until the Ollama response is ready
4. Pushes the AI response back to `server_app` via an ADB intent (`am start`)
5. `server_app` then chunks the response and sends it back to Phone A as SMS

```bash
cd backend
python adb_bridge.py --device <YOUR_DEVICE_ID>
```

Replace `<YOUR_DEVICE_ID>` with your Phone B's ADB device ID (find it with `adb devices`).

Optional flags:
```
--device, -d    (required) ADB device ID for Phone B
--backend, -b   Backend URL (default: http://localhost:8000)
```

### Terminal 3 — Ollama (if not already running)

```bash
ollama serve
```

### Alternative: Notification Monitor Mode

Instead of using the file-queue ADB bridge, there is an alternative `mobile_monitor.py` that scrapes SMS notifications from `adb dumpsys notification`. This is useful if the file-queue approach has issues:

```bash
cd backend/services
python trigger_response.py
```

> This mode monitors Android notification panels for incoming SMS and triggers the response flow directly.

## End-to-End Flow

1. User types a message in `sender_app` (Phone A)
2. `sender_app` chunks the message (if >160 chars) and sends as SMS to Phone B
3. `server_app` (Phone B) receives SMS, writes chunk JSON to disk queue
4. **ADB Bridge** (PC) detects new files, reads them via `adb shell run-as`, sends to FastAPI
5. FastAPI reassembles chunks, sends complete message to **Ollama**
6. Ollama generates a response, stored with a hash key
7. ADB Bridge polls for the result, then pushes it to `server_app` via ADB intent
8. `server_app` chunks the AI response and sends it back as SMS to Phone A
9. `sender_app` reassembles the response chunks and displays them in the chat UI

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/chunk` | Receive an SMS chunk |
| `POST` | `/api/process` | Process a complete message directly (bypass chunking) |
| `GET` | `/api/result/{hash}` | Poll for AI response by message hash |
| `GET` | `/api/buffer/status` | Debug: view chunk buffer state |

## Configuration

All settings are in `.env` — see [.env.example](.env.example) for the full list:

| Variable | Description |
|----------|-------------|
| `SERVER_DEVICE_ID` | ADB device ID of Phone B (run `adb devices`) |
| `TARGET_PHONE_NUMBER` | Phone number of Phone A (sender) |
| `OLLAMA_MODEL` | LLM model name (e.g. `gemma3:4b`) |
| `OLLAMA_HOST` | Ollama server URL (default: `http://localhost:11434`) |
| `SERVER_HOST` / `SERVER_PORT` | FastAPI bind address (default: `127.0.0.1:8000`) |
| `MAX_SMS_LENGTH` | SMS chunk size limit (default: `160`) |
| `CHUNK_SEND_DELAY_MS` | Delay between sending SMS chunks in ms (default: `500`) |
| `MONITOR_POLL_INTERVAL` | Notification monitor polling interval in seconds |
| `MAX_POLL_ATTEMPTS` | Max polling attempts before timeout (default: `60`) |
| `ADB_CMD` | ADB executable path if not on system PATH |
| `LOG_LEVEL` | Logging level: `DEBUG`, `INFO`, `WARNING`, `ERROR` |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `adb devices` shows no device | Enable USB Debugging on Phone B, reconnect USB, accept the RSA prompt |
| ADB bridge can't access `sms_queue/` | The directory is created on first SMS. Send a test SMS to Phone B first |
| `server_app` not receiving SMS | Set `server_app` as the default SMS app on Phone B |
| Ollama timeout | Ensure `ollama serve` is running and the model is pulled (`ollama list`) |
| Chunks arriving out of order | Increase `CHUNK_SEND_DELAY_MS` in `.env` |
| Permission denied on SMS | Grant SMS permissions to both apps when prompted on first launch |

## Project Structure

```
Himmel/
├── backend/
│   ├── main.py                  # FastAPI server — chunk reassembly & Ollama routing
│   ├── adb_bridge.py            # ADB polling loop & intent push bridge
│   ├── models.py                # Pydantic request/response models
│   ├── requirements.txt         # Python dependencies
│   └── services/
│       ├── chunk_calculator.py  # SMS chunking logic (Python impl)
│       ├── mobile_monitor.py    # Alternative: notification-based SMS monitor
│       ├── ollama_service.py    # Ollama LLM client wrapper
│       └── trigger_response.py  # Manual response trigger via monitor
├── sender_app/                  # Flutter — Phone A chat UI
│   ├── pubspec.yaml
│   ├── android/                 # Android platform config + SMS permissions
│   └── lib/
│       ├── main.dart
│       ├── models/              # Message data model
│       ├── screens/             # Chat screen UI
│       ├── services/            # SMS sending, chunking, settings, listener
│       ├── theme/               # App theme & colors
│       └── widgets/             # Chat bubbles, input area, typing indicator
├── server_app/                  # Flutter — Phone B relay
│   ├── pubspec.yaml
│   ├── android/                 # Android platform config + default SMS app
│   │   └── app/src/main/kotlin/ # Custom Kotlin: SmsReceiver, MmsReceiver,
│   │                            #   HeadlessSmsSendService, MainActivity
│   └── lib/
│       ├── main.dart
│       ├── models/              # Pending message model
│       └── services/            # SMS queue, chunking, backend forwarding
├── .env.example                 # Environment variable template
├── .gitattributes               # Line ending normalization
└── .gitignore
```

## License

This project is provided as-is for personal and educational use.
