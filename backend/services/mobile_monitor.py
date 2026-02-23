import subprocess
import re
import time
import hashlib
import logging
import requests
import sys
import threading
import os
from typing import Dict, Optional
from datetime import datetime


# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Constants
API_URL = "http://localhost:8000/api/process"
RESULT_URL = "http://localhost:8000/api/result/{}"
ADB_CMD = "adb"
TARGET_PACKAGE = "com.google.android.apps.messaging"
SERVER_APP_COMPONENT = "com.example.server_app/.MainActivity"
# You should ideally load this from environment variables
DEFAULT_DEVICE_ID = "32001fffe8402687"

class PartialMessage:
    """Represents a message that is being reassembled from chunks."""
    def __init__(self, msg_id: str, sender: str, timestamp: int):
        self.msg_id = msg_id
        self.sender = sender
        self.timestamp = timestamp
        self.max_chunks = 1
        self.chunks: Dict[int, str] = {} # index -> payload (1-based)

    def add_chunk(self, index: int, total: Optional[int], payload: str):
        if total:
            self.max_chunks = total
        self.chunks[index] = payload

    @property
    def is_complete(self) -> bool:
        return len(self.chunks) == self.max_chunks

    def merge(self) -> str:
        """Merges chunks in order."""
        sorted_indices = sorted(self.chunks.keys())
        return "".join([self.chunks[i] for i in sorted_indices])

class MessageBuffer:
    """Manages the state of incoming message chunks."""
    def __init__(self):
        self.buffer: Dict[str, PartialMessage] = {}

    def process_chunk(self, sender: str, content: str, timestamp: int) -> Optional[dict]:
        """
        Parses raw SMS content and manages buffering.
        Returns a dict payload if a message is complete, otherwise None.
        """
        try:
            # Protocol: ID:<id> [M:<total>] I:<index> T:<payload>
            
            # 1. Extract ID
            id_match = re.search(r"ID:([a-fA-F0-9]+)", content)
            if not id_match:
                logger.debug(f"Ignored non-protocol SMS: {content[:30]}...")
                return None
            msg_id = id_match.group(1)

            # 2. Extract Metadata
            idx_match = re.search(r"I:(\d+)", content)
            index = int(idx_match.group(1)) if idx_match else 1

            total_match = re.search(r"M:(\d+)", content)
            total = int(total_match.group(1)) if total_match else None

            payload_match = re.search(r"T:(.*)", content, re.DOTALL)
            payload = payload_match.group(1) if payload_match else ""

            # 3. Buffer Logic
            if msg_id not in self.buffer:
                self.buffer[msg_id] = PartialMessage(msg_id, sender, timestamp)
            
            self.buffer[msg_id].add_chunk(index, total, payload)
            
            current_count = len(self.buffer[msg_id].chunks)
            total_count = self.buffer[msg_id].max_chunks
            logger.info(f"🧩 Processed Chunk {index}/{total_count} for ID {msg_id[:8]}...")

            # 4. Check Completion
            if self.buffer[msg_id].is_complete:
                full_text = self.buffer[msg_id].merge()
                logger.info(f"✅ Message {msg_id[:8]} Complete! Payload size: {len(full_text)}")
                
                # Prepare Result
                result = {
                    "sender": self.buffer[msg_id].sender,
                    "original_content": full_text,
                    "timestamp": self.buffer[msg_id].timestamp
                }
                
                # Cleanup
                del self.buffer[msg_id]
                return result

        except Exception as e:
            logger.error(f"Error parsing chunk content: {e}")
        
        return None

class MobileMonitor:
    """Services to monitor ADB for new SMS notifications."""
    def __init__(self, device_id: str = DEFAULT_DEVICE_ID):
        self.device_id = device_id
        self.buffer = MessageBuffer()
        # Adjusted regex for non-greedy sender matching
        self.bundle_regex = re.compile(r'sender=(.*?),\s*text=(.*?),\s*time=(\d+)', re.DOTALL)
        self.seen_hashes = set()
        
        self._check_connection()

    def _check_connection(self):
        """Verifies ADB connectivity."""
        try:
            res = subprocess.run([ADB_CMD, "devices"], capture_output=True, text=True)
            if self.device_id not in res.stdout:
                logger.warning(f"⚠️ Device {self.device_id} not found in ADB list!")
                logger.info(f"Available devices:\n{res.stdout.strip()}")
            else:
                logger.info(f"📱 Connected to device: {self.device_id}")
        except FileNotFoundError:
            logger.critical("❌ 'adb' command not found. Install Android Platform Tools.")
            sys.exit(1)

    def fetch_notifications(self) -> str:
        """Runs the adb dumpsys command."""
        try:
            cmd = [ADB_CMD, "-s", self.device_id, "shell", "dumpsys", "notification", "--noredact"]
            # Capture as bytes to handle potential encoding issues manually
            result = subprocess.run(cmd, capture_output=True, text=False)

            if result.returncode != 0:
                logger.warning(f"ADB returned error code {result.returncode}: {result.stderr.decode('utf-8', errors='replace')}")
                return ""
            
            raw_bytes = result.stdout
            
            # Try decoding as utf-8 first (standard), then utf-16 (windows adb quirk), then latin-1
            content = ""
            try:
                content = raw_bytes.decode('utf-8')
            except UnicodeDecodeError:
                try:
                    content = raw_bytes.decode('utf-16')
                except UnicodeDecodeError:
                    content = raw_bytes.decode('latin-1', errors='ignore')

            if not content:
                logger.warning("ADB returned empty stdout.")
                return ""

            # Debugging: Log data size occasionally or if specific patterns are missing
            if "NotificationRecord" not in content and len(content) > 0:
                 logger.debug(f"Fetched {len(content)} chars, but 'NotificationRecord' not found.")
            
            return content

        except Exception as e:
            logger.error(f"ADB Execution Error: {e}")
            return ""

    def send_sms(self, target: str, message: str, message_id: str = None):
        """Sends an SMS via Server App using ADB Intent."""
        try:
            logger.info(f"📤 Preparing to send to {target}...")
            logger.info(f"DEBUG: self.device_id = '{self.device_id}'")
            
            # Escape message for ADB shell - replace problematic characters
            # Use base64 encoding to safely pass any content through ADB
            import base64
            encoded_message = base64.b64encode(message.encode('utf-8')).decode('ascii')
            
            logger.info(f"📦 Encoded message length: {len(encoded_message)} (original: {len(message)})")
            logger.info(f"DEBUG: Message preview: {message[:100]}...")
            if message_id:
                logger.info(f"🔑 Using message ID: {message_id[:8]}...")
            
            # Construct ADB Command to launch Server App MainActivity with extras
            # Use -f 0x20000000 (FLAG_ACTIVITY_SINGLE_TOP) to reuse existing instance
            cmd = [
                ADB_CMD, "-s", self.device_id, "shell", "am", "start",
                "-n", SERVER_APP_COMPONENT,
                "-f", "0x20000000",  # FLAG_ACTIVITY_SINGLE_TOP
                "--es", "target", target,
                "--es", "message_b64", encoded_message,  # Send as base64
            ]
            
            # Add message_id if provided
            if message_id:
                cmd.extend(["--es", "message_id", message_id])
            
            logger.info(f"DEBUG: Full ADB command: {' '.join(cmd[:10])}... (truncated)")
            
            # Capture output for debugging
            result = subprocess.run(cmd, capture_output=True, text=True)
            
            if result.returncode == 0:
                 logger.info(f"✅ ADB Command Success. Stdout: {result.stdout.strip()}")
            else:
                 logger.error(f"❌ ADB Command Failed (Code {result.returncode}). Stderr: {result.stderr.strip()}")
                 
        except Exception as e:
            logger.error(f"❌ Failed to trigger SMS Intent: {e}")
            import traceback
            traceback.print_exc()
                 
        except Exception as e:
            logger.error(f"❌ Failed to trigger SMS Intent: {e}")

    def poll_and_respond(self, result_hash: str, sender: str):
        """Polls the backend until result is ready, then chunks and sends it."""
        logger.info(f"⏳ Polling for result {result_hash}...")
        url = RESULT_URL.format(result_hash)
        
        start_time = time.time()
        timeout = 120 # 2 minutes timeout
        
        while time.time() - start_time < timeout:
            try:
                resp = requests.get(url)
                if resp.status_code == 200:
                    data = resp.json()
                    status = data.get("status")
                    
                    if status == "Completed":
                        content = data.get("content")
                        logger.info(f"✅ AI Reply Generated! Length: {len(content)}")
                        
                        # Send Full Message (Server App will handle chunking)
                        # Pass the result_hash as message_id to preserve ID through the round trip
                        logger.info(f"📤 Sending Full Payload to Server App for {sender}")
                        logger.info(f"🔑 Using message ID: {result_hash[:8]}...")
                        self.send_sms(sender, content, message_id=result_hash)
                        logger.info("✨ Payload sent to ADB!")
                        return
                        
                    elif status == "Error":
                        logger.error("❌ Backend reported error processing message.")
                        return
                    else:
                        logger.info(f"Status: {status}...")
                else:
                    logger.warning(f"⚠️ Polling received {resp.status_code}: {resp.text}")
            except Exception as e:
                logger.error(f"⚠️ Polling Error: {e}")
            
            # Wait before next poll
            time.sleep(1)
                
        logger.error(f"⏰ Polling timeout for {result_hash}")

    def send_to_backend(self, payload: dict):
        """POSTs the complete message to the FastAPI backend."""
        try:
            logger.info(f"🚀 Sending to Backend: {payload['sender']}")
            response = requests.post(API_URL, json=payload)
            if response.status_code == 200:
                data = response.json()
                result_hash = data.get('hash')
                logger.info(f"✅ Backend Accepted. Hash: {result_hash}")
                
                # Start Polling Thread
                t = threading.Thread(target=self.poll_and_respond, args=(result_hash, payload['sender']))
                t.daemon = True
                t.start()
                
            else:
                logger.error(f"❌ Backend Error ({response.status_code}): {response.text}")
        except Exception as e:
            logger.error(f"❌ Connection Failed: {e}")

    def start_loop(self, interval: float = 2.0):
        """Starts the infinite monitoring loop."""
        logger.info("---------------------------------------------")
        logger.info(f"👀 MOBILE MONITOR SERVICE STARTED")
        logger.info(f"🎯 Target Package: {TARGET_PACKAGE}")
        logger.info(f"🔗 Backend API: {API_URL}")
        logger.info("---------------------------------------------")

        try:
            while True:
                raw_data = self.fetch_notifications()
                if not raw_data:
                    time.sleep(interval)
                    continue

                # Split by records to process individually
                records = raw_data.split('NotificationRecord')
                
                for record in records:
                    if TARGET_PACKAGE not in record:
                        continue
                    
                    matches = self.bundle_regex.findall(record)
                    for sender, text, timestamp in matches:
                        clean_sender = sender.strip()
                        clean_text = text.strip()
                        
                        # Dedup Logic
                        unique_str = f"{clean_sender}|{clean_text}|{timestamp}"
                        msg_hash = hashlib.md5(unique_str.encode()).hexdigest()
                        
                        if msg_hash not in self.seen_hashes:
                            # Log finding only for NEW messages
                            logger.info(f"📩 Detected SMS from {clean_sender}: {clean_text[:50]}")
                            self.seen_hashes.add(msg_hash)
                            
                            try:
                                ts_int = int(timestamp)
                                
                                # Process through buffer
                                result = self.buffer.process_chunk(clean_sender, clean_text, ts_int)
                                
                                if result:
                                    self.send_to_backend(result)
                                    
                            except ValueError:
                                logger.warning(f"Invalid timestamp found: {timestamp}")

                time.sleep(interval)
                
        except KeyboardInterrupt:
            logger.info("\n🛑 Monitor Service Stopped.")

if __name__ == "__main__":
    monitor = MobileMonitor()
    monitor.start_loop()
