import subprocess
import re
import time
import json
import os
import hashlib
import requests
from datetime import datetime
from typing import List, Dict, Optional
from pydantic import BaseModel, Field, computed_field

# --- CONFIGURATION ---
DATABASE_FILE = "sms_database.json"
ADB_CMD = "adb"
DEVICE_ID = "c8d76aa4"
TARGET_PACKAGE = "com.google.android.apps.messaging"
API_URL = "http://localhost:8000/api/process"

# --- 1. PYDANTIC MODEL (Client Side) ---
class SMS(BaseModel):
    sender: str
    content: str
    raw_timestamp: int
    readable_time: str
    
    @computed_field
    def msg_hash(self) -> str:
        unique_str = f"{self.sender}|{self.content}|{self.raw_timestamp}"
        return hashlib.md5(unique_str.encode()).hexdigest()

# --- 2. MESSAGE BUFFER ---
class PartialMessage:
    def __init__(self, msg_id, sender, timestamp):
        self.msg_id = msg_id
        self.sender = sender
        self.timestamp = timestamp
        self.max_chunks = 1 # Default, updated if 'M' tag found
        self.chunks: Dict[int, str] = {} # index -> payload

    def add_chunk(self, index, total, payload):
        if total:
            self.max_chunks = total
        self.chunks[index] = payload

    @property
    def is_complete(self):
        return len(self.chunks) == self.max_chunks

    def merge(self):
        sorted_indices = sorted(self.chunks.keys())
        return "".join([self.chunks[i] for i in sorted_indices])

class MessageBuffer:
    def __init__(self):
        # msg_id -> PartialMessage
        self.buffer: Dict[str, PartialMessage] = {}

    def process_raw_sms(self, sms: SMS):
        # Parse Content for Headers
        # Format: ID:<id> \n [M:<total> \n] I:<index> \n T:<payload>
        
        try:
            content = sms.content
            
            # Extract ID
            id_match = re.search(r"ID:([a-fA-F0-9]+)", content)
            if not id_match:
                print(f"⚠️ Non-protocol SMS received: {content[:20]}...")
                return
            msg_id = id_match.group(1)

            # Extract Index
            idx_match = re.search(r"I:(\d+)", content)
            index = int(idx_match.group(1)) if idx_match else 1

            # Extract Total (Optional, usually in chunk 1)
            total_match = re.search(r"M:(\d+)", content)
            total = int(total_match.group(1)) if total_match else None

            # Extract Payload (Everything after T:)
            payload_match = re.search(r"T:(.*)", content, re.DOTALL)
            payload = payload_match.group(1) if payload_match else ""

            # Logic
            if msg_id not in self.buffer:
                self.buffer[msg_id] = PartialMessage(msg_id, sms.sender, sms.raw_timestamp)
            
            self.buffer[msg_id].add_chunk(index, total, payload)
            
            print(f"🧩 Processed Chunk {index} for ID {msg_id[:8]}... ({len(self.buffer[msg_id].chunks)}/{self.buffer[msg_id].max_chunks})")

            # Check Completeness
            if self.buffer[msg_id].is_complete:
                full_text = self.buffer[msg_id].merge()
                print(f"✅ Message Complete! Sending to API...")
                self.send_to_api(self.buffer[msg_id], full_text)
                del self.buffer[msg_id]

        except Exception as e:
            print(f"Error parsing chunk: {e}")

    def send_to_api(self, partial: PartialMessage, full_text: str):
        payload = {
            "sender": partial.sender,
            "original_content": full_text,
            "timestamp": partial.timestamp,
            "total_chunks": partial.max_chunks
        }
        
        try:
            response = requests.post(API_URL, json=payload)
            if response.status_code == 200:
                data = response.json()
                print(f"🚀 Sent to Backend. Trace Hash: {data['hash']}")
            else:
                print(f"❌ API Error: {response.text}")
        except Exception as e:
            print(f"❌ Failed to connect to API: {e}")


# --- 3. THE LIVE MONITOR ---
class SMSMonitor:
    def __init__(self):
        self.buffer = MessageBuffer()
        # Updated Regex: Uses non-greedy match for sender to handle commas also
        self.bundle_regex = re.compile(r'sender=(.*?),\s*text=(.*?),\s*time=(\d+)', re.DOTALL)
        self.seen_hashes = set() # Simple dedup for raw inputs
        self._check_adb()

    def _check_adb(self):
        """Verifies ADB connection before starting."""
        try:
            res = subprocess.run([ADB_CMD, "devices"], capture_output=True, text=True)
            print(f"📡 ADB Check:\n{res.stdout.strip()}")
            if "device" not in res.stdout or "List of devices attached\n\n" == res.stdout:
                print("⚠️ No device connected via ADB! Monitoring might return empty.")
        except FileNotFoundError:
            print("❌ ADB not found in PATH. Please install Android Platform Tools.")

    def fetch_dump(self):
        try:
            cmd = [ADB_CMD]
            if DEVICE_ID:
                cmd.extend(["-s", DEVICE_ID])
            cmd.extend(['shell', 'dumpsys', 'notification', '--noredact'])

            result = subprocess.run(
                cmd,
                capture_output=True, text=True, encoding='utf-8', errors='ignore'
            )
            if result.returncode != 0:
                print(f"⚠️ ADB Error: {result.stderr.strip()}")
                return ""
            return result.stdout
        except Exception as e:
            print(f"⚠️ execution error: {e}")
            return ""

    def process_stream(self):
        raw_data = self.fetch_dump()
        records = raw_data.split('NotificationRecord')

        for record in records:
            if TARGET_PACKAGE not in record:
                continue

            matches = self.bundle_regex.findall(record)
            
            for sender, text, timestamp in matches:
                clean_sender = sender.strip()
                clean_text = text.strip()
                
                try:
                    ts_int = int(timestamp)
                    readable = datetime.fromtimestamp(ts_int / 1000.0).strftime('%Y-%m-%d %H:%M:%S')
                    
                    sms = SMS(
                        sender=clean_sender,
                        content=clean_text,
                        raw_timestamp=ts_int,
                        readable_time=readable
                    )

                    if sms.msg_hash not in self.seen_hashes:
                        self.seen_hashes.add(sms.msg_hash)
                        self.buffer.process_raw_sms(sms)

                except Exception as e:
                    print(f"Error parsing bundle: {e}")

    def start(self):
        print("---------------------------------------------")
        print(f"👀 SMS MONITOR RUNNING (Smart Mode)")
        print(f"🎯 Target App: {TARGET_PACKAGE}")
        print(f"🔗 API: {API_URL}")
        print("---------------------------------------------")
        
        try:
            while True:
                self.process_stream()
                time.sleep(2)
        except KeyboardInterrupt:
            print("\n🛑 Monitor Stopped.")

if __name__ == "__main__":
    monitor = SMSMonitor()
    monitor.start()




