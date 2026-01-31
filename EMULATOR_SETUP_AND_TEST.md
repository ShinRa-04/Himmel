# Emulator Setup and Test Guide (From Scratch)

This guide covers everything you need to set up and test the Himmel project using an Android Emulator (Android Studio).

## Phase 1: Core Prerequisites Installation

Before running any code, ensure you have these tools installed.

### 1. Install Android Sudio & Setup Emulator
1.  **Download & Install**: [Android Studio](https://developer.android.com/studio).
2.  **Open Android Studio**:
    *   Click usually on "More Actions" > **Virtual Device Manager** (or Device Manager in the UI).
3.  **Create Device**:
    *   Click **Create Device**.
    *   Choose **Phone** -> **Pixel 7** (or similar).
    *   Select a System Image: **API 35** (or latest available). Download it if needed.
    *   Click **Finish**.
4.  **Start Emulator**: Click the "Play" button next to your new device. Wait for it to boot to the home screen.

### 2. Install Flutter SDK
1.  **Download**: [Flutter Windows Install](https://docs.flutter.dev/get-started/install/windows).
2.  **Extract**: Place it in `C:\flutter` (do not put it in `Program Files`).
3.  **Update Path**: Add `C:\flutter\bin` to your User Environment Variables "Path".
4.  **Verify**: Open a **new** terminal and run:
    ```powershell
    flutter doctor
    ```
    *   *Resolve any issues marked with [X] (mainly Android licenses).*
    *   *Run `flutter doctor --android-licenses` if asked.*

### 3. Install Python & Ollama
1.  **Python**: Install Python 3.10+ from [python.org](https://www.python.org/downloads/).
    *   *Make sure to check "Add Python to PATH" during installation.*
2.  **Ollama**: Download from [ollama.com](https://ollama.com) and install.
    *   Open terminal and run: `ollama pull gemma3:4b`
    *   *(If `gemma3` fails, try `ollama pull llama3` and update `backend/services/ollama_service.py` to match).*

---

## Phase 2: Project Setup

Assuming you are in the `Himmel` folder.

### 1. Backend Setup
1.  Open a terminal in `Himmel/backend`.
2.  Install dependencies:
    ```powershell
    pip install fastapi uvicorn requests ollama
    ```

### 2. Flutter Dependencies
1.  Open a terminal in `Himmel/server_app`.
2.  Get dependencies:
    ```powershell
    flutter pub get
    ```

---

## Phase 3: Running the System

You will need **3 separate terminal windows**.

### Terminal 1: Result Backend
Navigate to `Himmel/backend` and run:
```powershell
python -m uvicorn main:app --reload
```
*   *Success*: You see `Uvicorn running on http://127.0.0.1:8000`.

### Terminal 2: Mobile Monitor
Navigate to `Himmel/backend` (make sure you are in the `backend` folder!) and run:
```powershell
python -m services.mobile_monitor
```
*   *Success*: You see `👀 MOBILE MONITOR SERVICE STARTED` and `Connected to device: emulator-5554`.

### Terminal 3: Run the App
Navigate to `Himmel/server_app` and run:
```powershell
flutter run
```
*   It should detect the running emulator.
*   Once the app launches on the emulator:
    *   **Allow SMS Permissions** when prompted.
    *   The app screen should say "🟢 Server Ready" (or "Not Default SMS App", which is fine for testing).

---

## Phase 4: Validating & Testing

Now simulate an incoming SMS to trigger the entire pipeline.

1.  Open a **4th terminal** (or use the Flutter terminal).
2.  Run this command to send a fake SMS to the emulator:
    ```powershell
    adb emu sms send "123456789" "Hello Himmel, are you working?"
    ```
3.  **Watch the Flow**:
    *   **Emulator**: A notification pops up "New Message from 123456789".
    *   **Terminal 2 (Monitor)**: `📩 Detected SMS from 123456789`.
    *   **Terminal 1 (Backend)**: Shows processing logs.
    *   **Terminal 2 (Monitor)**: After a few seconds -> `✅ AI Reply Generated!`.
    *   **Emulator**: The `server_app` sends the reply. You might see the "Messages" app on the emulator show the sent reply in the thread.

## Common Issues
*   **Monitor doesn't see SMS**: The emulator's notification shade might need to be "polled" by the system. If you don't see logs in Terminal 2, try sending the SMS again.
*   **App crashes**: Ensure `adb` is in your path and you accepted permissions on the emulator.
