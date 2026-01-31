import requests
import time
import subprocess
import base64
import sys

API_URL = "http://localhost:8000/api/process"
RESULT_URL = "http://localhost:8000/api/result/{}"
ADB_CMD = "adb"
SERVER_APP_COMPONENT = "com.example.server_app/.MainActivity"

def test_flow(sender, message):
    print(f"🚀 Sending Manual Trigger: '{message}' from {sender}")
    
    # 1. Send to Backend
    payload = {
        "sender": sender,
        "original_content": message,
        "timestamp": int(time.time() * 1000),
        "total_chunks": 1
    }
    
    try:
        res = requests.post(API_URL, json=payload)
        data = res.json()
        result_hash = data.get("hash")
        print(f"✅ Backend Accepted. Hash: {result_hash}")
    except Exception as e:
        print(f"❌ Backend Error: {e}")
        return

    # 2. Poll for Result
    print("⏳ Waiting for AI (Ollama)...")
    for _ in range(30): # 60 seconds max
        res = requests.get(RESULT_URL.format(result_hash))
        if res.status_code == 200:
            r_data = res.json()
            if r_data.get("status") == "Completed":
                reply = r_data.get("content")
                print(f"\n✨ AI Replied: {reply}")
                
                # 3. Trigger ADB Intent
                send_adb_intent(sender, reply)
                return
            else:
                print(".", end="", flush=True)
        time.sleep(2)
        
    print("\n❌ Timeout waiting for AI.")

def send_adb_intent(target, message):
    print(f"📤 Forwarding to Android Device via ADB...")
    encoded_message = base64.b64encode(message.encode('utf-8')).decode('ascii')
    
    cmd = [
        ADB_CMD, "shell", "am", "start",
        "-n", SERVER_APP_COMPONENT,
        "--es", "target", target,
        "--es", "message_b64", encoded_message,
        "--activity-clear-top"
    ]
    
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        print(f"✅ Signal Sent to App! Check your Emulator Screen.")
    else:
        print(f"❌ ADB Failed: {res.stderr}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        msg = " ".join(sys.argv[1:])
    else:
        msg = "Hello AI, this is a manual test."
        
    test_flow("123456789", msg)
