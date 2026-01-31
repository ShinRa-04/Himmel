import requests
import time
import hashlib

API_URL = "http://localhost:8000/api/process"
RESULT_URL = "http://localhost:8000/api/result"

def test_backend_flow():
    print("Testing Backend Flow...")
    
    # 1. Simulate a merged message payload (what parser.py sends after merging)
    test_payload = {
        "sender": "+15550101",
        "original_content": "What I want to know is, how do I get the same level of responsiveness as I get in GUI in Terminal as well ?",
        "timestamp": int(time.time() * 1000),
        "total_chunks": 1
    }
    
    # 2. Send to Backend
    print(f"Sending payload: {test_payload}")
    try:
        response = requests.post(API_URL, json=test_payload)
        response.raise_for_status()
        data = response.json()
        result_hash = data.get("hash")
        print(f"Success! Hash: {result_hash}")
        
    except Exception as e:
        print(f"Failed to send: {e}")
        return

    # 3. Poll for Result
    print("Polling for result...")
    for i in range(10):
        try:
            res = requests.get(f"{RESULT_URL}/{result_hash}")
            if res.status_code == 200:
                final_data = res.json()
                if final_data.get("status") == "Processing":
                    print(".", end="", flush=True)
                else:
                    print("\nResult Received!")
                    print(final_data)
                    break
            elif res.status_code == 500:
                 print("\nServer Error!")
                 break
        except Exception as e:
             print(f"\nPolling error: {e}")
        
        time.sleep(2)

if __name__ == "__main__":
    test_backend_flow()
