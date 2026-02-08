import sys
import logging
import requests
import time
from mobile_monitor import MobileMonitor

# Setup basic logging
logging.basicConfig(level=logging.DEBUG, format="%(asctime)s [%(levelname)s] %(message)s")

# Configure this if you have multiple devices connected
SERVER_DEVICE_ID = "7eb67b3f" 
API_PROCESS_URL = "http://127.0.0.1:8000/api/process"

def main():
    print("---------------------------------------------")
    print(" MANUAL RESPONSE TRIGGER (FULL FLOW)")
    print("---------------------------------------------")
    
    if len(sys.argv) < 3:
        # Interactive Mode
        phone_number = input("Enter Target Phone Number: ").strip()
        message_text = input("Enter Test Message: ").strip()
    else:
        # CLI Mode
        phone_number = sys.argv[1]
        message_text = sys.argv[2]
        
    device_id = SERVER_DEVICE_ID
    if len(sys.argv) >= 4:
         device_id = sys.argv[3]
         
    if not device_id:
        print("Note: SERVER_DEVICE_ID is empty. Using default from MobileMonitor or prompting.")
        inp = input("Enter Server Device ID (Press Enter to use default): ").strip()
        if inp:
            device_id = inp

    if not phone_number or not message_text:
        print("❌ Error: Missing phone number or message.")
        return

    # 1. POST to Backend
    print(f"🚀 sending POST to {API_PROCESS_URL}...")
    payload = {
        "sender": phone_number,
        "original_content": message_text,
        "timestamp": int(time.time())
    }
    
    try:
        resp = requests.post(API_PROCESS_URL, json=payload)
        if resp.status_code != 200:
             print(f"❌ Backend POST Failed: {resp.status_code} {resp.text}")
             return
             
        data = resp.json()
        result_hash = data.get("hash")
        print(f"✅ Backend Accepted. Generated Hash: {result_hash}")
        
    except Exception as e:
        print(f"❌ Connection Error: {e}")
        return

    # 2. Start Monitoring
    print(f"🚀 Triggering polling for Hash: {result_hash} -> To: {phone_number} on Device: {device_id or 'Default'}")
    
    try:
        if device_id:
            monitor = MobileMonitor(device_id=device_id)
        else:
            monitor = MobileMonitor()
            
        monitor.poll_and_respond(result_hash, phone_number)
    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    main()
