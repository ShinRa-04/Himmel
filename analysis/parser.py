import subprocess
import re
import time
import json
import os
import hashlib
from datetime import datetime
from typing import List
from pydantic import BaseModel, Field, computed_field

# --- CONFIGURATION ---
DATABASE_FILE = "sms_database.json"
ADB_CMD = "adb"
DEVICE_ID = "10BE7H2J7S000T7"  # Add your device ID here if you want to target a specific device
TARGET_PACKAGE = "com.google.android.apps.messaging"  # As seen in your Android 16 logs

# --- 1. PYDANTIC MODEL ---
class SMS(BaseModel):
    sender: str
    content: str
    raw_timestamp: int
    readable_time: str
    
    @computed_field
    def msg_hash(self) -> str:
        """Generates a unique ID based on content + time to prevent duplicates."""
        # We use strict hashing so even if you restart the script, it knows what it saw before.
        unique_str = f"{self.sender}|{self.content}|{self.raw_timestamp}"
        return hashlib.md5(unique_str.encode()).hexdigest()

# --- 2. PERSISTENCE LAYER (JSON) ---
class StorageManager:
    def __init__(self, filename):
        self.filename = filename
        self.seen_hashes = set()
        self._load_existing_hashes()

    def _load_existing_hashes(self):
        """Loads previous history so we don't save duplicates on restart."""
        if not os.path.exists(self.filename):
            return
        
        try:
            with open(self.filename, 'r', encoding='utf-8') as f:
                data = json.load(f)
                for item in data:
                    # We reconstruct the hash from the saved data to populate memory
                    unique_str = f"{item['sender']}|{item['content']}|{item['raw_timestamp']}"
                    h = hashlib.md5(unique_str.encode()).hexdigest()
                    self.seen_hashes.add(h)
            print(f"📦 Loaded {len(self.seen_hashes)} historical messages from JSON.")
        except (json.JSONDecodeError, KeyError):
            print("⚠️ Database corrupted or empty. Starting fresh.")

    def save_new_message(self, message_obj: SMS):
        """Appends the new message to the JSON file."""
        if message_obj.msg_hash in self.seen_hashes:
            return False  # Already exists
        
        # 1. Update Memory
        self.seen_hashes.add(message_obj.msg_hash)
        
        # 2. Update File (Read-Modify-Write pattern for safety)
        current_data = []
        if os.path.exists(self.filename):
            try:
                with open(self.filename, 'r', encoding='utf-8') as f:
                    current_data = json.load(f)
            except:
                current_data = []

        current_data.append(message_obj.model_dump())

        with open(self.filename, 'w', encoding='utf-8') as f:
            json.dump(current_data, f, indent=4, ensure_ascii=False)
            
        return True

# --- 3. THE LIVE MONITOR ---
class SMSMonitor:
    def __init__(self):
        self.storage = StorageManager(DATABASE_FILE)
        # Regex specifically tuned for your Android 16 Bundle format
        self.bundle_regex = re.compile(r'sender=([^,]+),\s*text=(.*?),\s*time=(\d+)', re.DOTALL)

    def fetch_dump(self):
        try:
            cmd = [ADB_CMD]
            if DEVICE_ID:
                cmd.extend(["-s", DEVICE_ID])
            cmd.extend(['shell', 'dumpsys', 'notification', '--noredact'])

            return subprocess.run(
                cmd,
                capture_output=True, text=True, encoding='utf-8', errors='ignore'
            ).stdout
        except:
            return ""

    def process_stream(self):
        raw_data = self.fetch_dump()
        records = raw_data.split('NotificationRecord')

        for record in records:
            # FILTER: Strict check for Google Messages (SMS)
            if TARGET_PACKAGE not in record:
                continue

            # PARSE: Look for the hidden 'android.messages' Bundle
            matches = self.bundle_regex.findall(record)
            
            for sender, text, timestamp in matches:
                # Clean up extracted data
                clean_sender = sender.strip()
                clean_text = text.strip()
                
                # Create Pydantic Object
                try:
                    ts_int = int(timestamp)
                    readable = datetime.fromtimestamp(ts_int / 1000.0).strftime('%Y-%m-%d %H:%M:%S')
                    
                    sms = SMS(
                        sender=clean_sender,
                        content=clean_text,
                        raw_timestamp=ts_int,
                        readable_time=readable
                    )

                    # Save if new
                    if self.storage.save_new_message(sms):
                        print(f"\n[✨ NEW SMS] {sms.readable_time}")
                        print(f"   From: {sms.sender}")
                        print(f"   Body: {sms.content}")
                        print(f"   Saved to {DATABASE_FILE}")

                except Exception as e:
                    print(f"Error parsing bundle: {e}")

    def start(self):
        print("---------------------------------------------")
        print(f"👀 SMS MONITOR RUNNING")
        print(f"🎯 Target App: {TARGET_PACKAGE}")
        print(f"💾 Storage: {os.path.abspath(DATABASE_FILE)}")
        print("---------------------------------------------")
        
        try:
            while True:
                self.process_stream()
                time.sleep(2) # Check every 2 seconds
        except KeyboardInterrupt:
            print("\n🛑 Monitor Stopped.")

# --- RUN ---
if __name__ == "__main__":
    monitor = SMSMonitor()
    monitor.start()



