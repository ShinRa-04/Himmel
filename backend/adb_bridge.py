"""
ADB Bridge for Himmel Server

This script runs on the PC and:
1. Monitors the server phone for incoming SMS chunks via ADB
2. Forwards chunks to the local backend API
3. Polls for results
4. Pushes responses back to server_app via ADB intent

Usage:
    python adb_bridge.py --device <device_id>
"""

import subprocess
import json
import time
import re
import hashlib
import argparse
import base64
import requests
from datetime import datetime
from typing import Dict, Optional
from pathlib import Path

# Configuration
BACKEND_URL = "http://localhost:8000"
CHUNK_ENDPOINT = f"{BACKEND_URL}/api/chunk"
RESULT_ENDPOINT = f"{BACKEND_URL}/api/result"
POLL_INTERVAL = 0.3  # Poll every 300ms for faster response
CHUNK_DIR_ON_PHONE = "/data/data/com.example.server_app/files/sms_queue"
SERVER_APP_COMPONENT = "com.example.server_app/.MainActivity"


class AdbBridge:
    def __init__(self, device_id: str):
        self.device_id = device_id
        self.seen_files: set = set()
        self.pending_results: Dict[str, dict] = {}  # result_hash -> {sender, started_at}
        
    def adb_cmd(self, *args) -> subprocess.CompletedProcess:
        """Run an ADB command for this device."""
        cmd = ["adb", "-s", self.device_id] + list(args)
        return subprocess.run(cmd, capture_output=True, text=True)
    
    def adb_run_as(self, command: str) -> subprocess.CompletedProcess:
        """Run a command as the server_app package (to access app-private files)."""
        return self.adb_cmd("shell", f"run-as com.example.server_app {command}")
    
    def check_device(self) -> bool:
        """Verify device is connected."""
        result = subprocess.run(["adb", "devices"], capture_output=True, text=True)
        return self.device_id in result.stdout
    
    def list_chunk_files(self) -> list:
        """List SMS chunk files on the phone."""
        # Use run-as to access app-private directory
        result = self.adb_run_as("ls files/sms_queue/ 2>/dev/null")
        if result.returncode != 0:
            return []
        
        files = [f.strip() for f in result.stdout.strip().split('\n') if f.strip() and f.endswith('.json')]
        return files
    
    def read_chunk_file(self, filename: str) -> Optional[dict]:
        """Read and parse a chunk file from the phone."""
        # Use run-as to access app-private directory
        result = self.adb_run_as(f"cat files/sms_queue/{filename}")
        
        if result.returncode != 0:
            print(f"❌ Failed to read {filename}: {result.stderr}")
            return None
        
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as e:
            print(f"❌ Invalid JSON in {filename}: {e}")
            print(f"   Content: {result.stdout[:100]}")
            return None
    
    def delete_chunk_file(self, filename: str):
        """Delete a processed chunk file from the phone."""
        self.adb_run_as(f"rm files/sms_queue/{filename}")
        print(f"🗑️  Deleted {filename}")
    
    def forward_chunk_to_backend(self, chunk_data: dict) -> Optional[dict]:
        """Forward a chunk to the backend API."""
        try:
            response = requests.post(
                CHUNK_ENDPOINT,
                json={
                    "sender": chunk_data["sender"],
                    "content": chunk_data["body"],
                    "timestamp": chunk_data["timestamp"]
                },
                timeout=10
            )
            
            if response.status_code == 200:
                return response.json()
            else:
                print(f"❌ Backend error: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            print(f"❌ Failed to forward to backend: {e}")
            return None
    
    def poll_result(self, result_hash: str) -> Optional[dict]:
        """Poll for a result from the backend."""
        try:
            response = requests.get(f"{RESULT_ENDPOINT}/{result_hash}", timeout=5)
            
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 404:
                return {"status": "Processing"}
            else:
                return {"status": "Error", "error": response.text}
                
        except Exception as e:
            print(f"⚠️ Poll error: {e}")
            return None
    
    def push_response_to_phone(self, sender: str, message: str, message_id: str):
        """Push a response to the server_app via ADB intent."""
        # Base64 encode the message to handle special characters
        message_b64 = base64.b64encode(message.encode('utf-8')).decode('utf-8')
        
        print(f"📤 Pushing response to server_app...")
        print(f"   Target: {sender}")
        print(f"   Message ID: {message_id}")
        print(f"   Message length: {len(message)} chars")
        print(f"   Base64 length: {len(message_b64)} chars")
        
        # Build the intent command with FLAG_ACTIVITY_SINGLE_TOP
        # Include message_id so server_app uses the same ID for the response
        cmd = [
            "shell", "am", "start",
            "-n", SERVER_APP_COMPONENT,
            "-f", "0x20000000",  # FLAG_ACTIVITY_SINGLE_TOP
            "--es", "target", sender,
            "--es", "message_b64", message_b64,
            "--es", "message_id", message_id,  # Preserve original message ID
        ]
        
        result = self.adb_cmd(*cmd)
        
        if result.returncode == 0:
            print(f"✅ Intent delivered to server_app")
            print(f"   ADB output: {result.stdout.strip()}")
        else:
            print(f"❌ Failed to push response: {result.stderr}")
    
    def process_chunks(self):
        """Check for new chunks and process them."""
        files = self.list_chunk_files()
        
        for filename in files:
            if filename in self.seen_files:
                continue
            
            print(f"\n📩 New chunk file: {filename}")
            
            # Read the chunk
            chunk_data = self.read_chunk_file(filename)
            if not chunk_data:
                self.seen_files.add(filename)
                continue
            
            sender = chunk_data.get("sender", "Unknown")
            body = chunk_data.get("body", "")
            
            print(f"   From: {sender}")
            print(f"   Content: {body[:60]}...")
            
            # Forward to backend
            result = self.forward_chunk_to_backend(chunk_data)
            
            if result:
                is_complete = result.get("is_complete", False)
                
                if is_complete:
                    result_hash = result.get("result_hash")
                    print(f"✅ Message complete! Waiting for result: {result_hash[:8]}...")
                    
                    # Track this for polling
                    self.pending_results[result_hash] = {
                        "sender": sender,
                        "started_at": datetime.now()
                    }
                else:
                    chunks_recv = result.get("chunks_received", 0)
                    chunks_exp = result.get("chunks_expected", "?")
                    print(f"🧩 Buffered chunk {chunks_recv}/{chunks_exp}")
            
            # Delete the file and mark as seen
            self.delete_chunk_file(filename)
            self.seen_files.add(filename)
    
    def check_pending_results(self):
        """Poll for pending results and push responses."""
        to_remove = []
        
        for result_hash, info in self.pending_results.items():
            # Check for timeout (5 minutes)
            age = (datetime.now() - info["started_at"]).total_seconds()
            if age > 300:
                print(f"⏰ Timeout for {result_hash[:8]}")
                to_remove.append(result_hash)
                continue
            
            result = self.poll_result(result_hash)
            
            if result and result.get("status") == "Completed":
                content = result.get("content", "")
                sender = info["sender"]
                
                print(f"\n🤖 Got AI response for {sender}!")
                print(f"   Message ID: {result_hash}")
                print(f"   Length: {len(content)} chars")
                print(f"   Preview: {content[:80]}...")
                
                # Push response to phone WITH the original message ID
                self.push_response_to_phone(sender, content, result_hash)
                to_remove.append(result_hash)
                
            elif result and result.get("status") == "Error":
                print(f"❌ Error for {result_hash[:8]}: {result.get('error')}")
                to_remove.append(result_hash)
        
        for h in to_remove:
            del self.pending_results[h]
    
    def run(self):
        """Main loop."""
        print("\n" + "=" * 60)
        print("   🌤️  HIMMEL ADB BRIDGE")
        print("=" * 60)
        print(f"   📱 Device: {self.device_id}")
        print(f"   🔗 Backend: {BACKEND_URL}")
        print(f"   ⚡ Poll interval: {POLL_INTERVAL}s")
        print("=" * 60)
        
        if not self.check_device():
            print(f"\n❌ Device {self.device_id} not found!")
            print("   Run 'adb devices' to see connected devices")
            return
        
        print("\n✅ Device connected!")
        
        # Test directory access
        test_result = self.adb_run_as("ls files/sms_queue/ 2>&1")
        if "No such file" in test_result.stdout or "No such file" in test_result.stderr:
            print("📂 SMS queue directory doesn't exist yet (will be created on first SMS)")
        elif test_result.returncode != 0:
            print(f"⚠️  Warning: Cannot access sms_queue - {test_result.stderr}")
        else:
            existing = [f for f in test_result.stdout.strip().split('\n') if f.strip()]
            if existing:
                print(f"📂 Found {len(existing)} existing file(s) in queue")
        
        print("\n👂 Listening for incoming SMS chunks...")
        print("   (Press Ctrl+C to stop)\n")
        
        try:
            while True:
                self.process_chunks()
                self.check_pending_results()
                time.sleep(POLL_INTERVAL)
                
        except KeyboardInterrupt:
            print("\n\n🛑 Bridge stopped.")


def main():
    parser = argparse.ArgumentParser(description="Himmel ADB Bridge")
    parser.add_argument("--device", "-d", required=True, help="ADB device ID")
    parser.add_argument("--backend", "-b", default="http://localhost:8000", help="Backend URL")
    
    args = parser.parse_args()
    
    global BACKEND_URL, CHUNK_ENDPOINT, RESULT_ENDPOINT
    BACKEND_URL = args.backend
    CHUNK_ENDPOINT = f"{BACKEND_URL}/api/chunk"
    RESULT_ENDPOINT = f"{BACKEND_URL}/api/result"
    
    bridge = AdbBridge(args.device)
    bridge.run()


if __name__ == "__main__":
    main()
