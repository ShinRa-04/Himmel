from fastapi import FastAPI, BackgroundTasks, HTTPException
from typing import Dict, Optional
import hashlib
import re
import logging
from datetime import datetime
from models import IncomingSMS, ProcessedSMS, IncomingChunk
from services.ollama_service import OllamaService

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s │ %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)

app = FastAPI()

@app.on_event("startup")
async def startup_event():
    """Print startup banner."""
    print("\n" + "=" * 60)
    print("   🌤️  HIMMEL BACKEND SERVER")
    print("=" * 60)
    print("   📡 Listening for SMS chunks on /api/chunk")
    print("   🤖 Ollama integration ready")
    print("   📦 Result store initialized")
    print("=" * 60 + "\n")
    logger.info("Server started - waiting for chunks...")

# In-memory result store: { hash: ProcessedSMS }
results_store: Dict[str, ProcessedSMS] = {}
# Status store to distinguish between "Processing" and "Not Found"
processing_status: Dict[str, str] = {}

# ============ Chunk Buffer for Reassembly ============

class PartialMessage:
    """Represents a message being reassembled from chunks."""
    def __init__(self, msg_id: str, sender: str, timestamp: int):
        self.msg_id = msg_id
        self.sender = sender
        self.timestamp = timestamp
        self.max_chunks = 1
        self.chunks: Dict[int, str] = {}  # index -> payload (1-based)
        self.created_at = datetime.now()

    def add_chunk(self, index: int, total: Optional[int], payload: str):
        if total:
            self.max_chunks = total
        self.chunks[index] = payload

    @property
    def is_complete(self) -> bool:
        return len(self.chunks) == self.max_chunks

    def merge(self) -> str:
        """Merge chunks in order."""
        sorted_indices = sorted(self.chunks.keys())
        return "".join([self.chunks[i] for i in sorted_indices])

# Chunk buffer: msg_id -> PartialMessage
chunk_buffer: Dict[str, PartialMessage] = {}

def parse_protocol_message(content: str) -> Optional[Dict]:
    """
    Parse a protocol message.
    Format: ID:<hash>\n[M:<total>\n]I:<index>\nT:<payload>
    Returns dict with id, index, total (optional), payload
    """
    try:
        # Extract ID
        id_match = re.search(r'ID:([a-fA-F0-9]+)', content)
        if not id_match:
            return None
        msg_id = id_match.group(1)

        # Extract Index
        idx_match = re.search(r'I:(\d+)', content)
        index = int(idx_match.group(1)) if idx_match else 1

        # Extract Total (optional)
        total_match = re.search(r'M:(\d+)', content)
        total = int(total_match.group(1)) if total_match else None

        # Extract Payload (everything after T:)
        payload_match = re.search(r'T:(.*)', content, re.DOTALL)
        payload = payload_match.group(1) if payload_match else ""

        return {
            'id': msg_id,
            'index': index,
            'total': total,
            'payload': payload
        }
    except Exception as e:
        print(f"Error parsing protocol message: {e}")
        return None

# ============ Background Processing ============

def process_sms_background(incoming: IncomingSMS, result_hash: str):
    """
    Background task to process the SMS with Ollama and calculate chunks.
    """
    try:
        logger.info("🤖 Sending to Ollama...")
        logger.info(f"   Query: {incoming.original_content[:80]}{'...' if len(incoming.original_content) > 80 else ''}")
        
        # 1. Generate Reply
        reply_text = OllamaService.generate_reply(incoming.original_content)
        
        logger.info(f"✅ Ollama responded! Length: {len(reply_text)} chars")
        logger.info(f"   Response: {reply_text[:80]}{'...' if len(reply_text) > 80 else ''}")
        
        # 2. Create Result Object (No chunking needed here)
        result = ProcessedSMS(
            sender=incoming.sender,
            content=reply_text,
            timestamp=incoming.timestamp,
            hash=result_hash
        )
        
        # 4. Store Result
        results_store[result_hash] = result
        processing_status[result_hash] = "Completed"
        logger.info(f"📦 Result stored: {result_hash[:8]}... → Ready for pickup")
        
    except Exception as e:
        logger.error(f"❌ Error processing SMS {result_hash[:8]}: {e}")
        processing_status[result_hash] = "Error"

# ============ API Endpoints ============

@app.post("/api/chunk")
async def receive_chunk(chunk: IncomingChunk, background_tasks: BackgroundTasks):
    """
    Receive a single SMS chunk and buffer it.
    When all chunks are received, automatically process the complete message.
    """
    # Parse the protocol message
    parsed = parse_protocol_message(chunk.content)
    
    if not parsed:
        logger.warning(f"⚠️ Invalid protocol format from {chunk.sender}")
        raise HTTPException(status_code=400, detail="Invalid protocol format")
    
    msg_id = parsed['id']
    index = parsed['index']
    total = parsed['total']
    payload = parsed['payload']
    
    logger.info("=" * 50)
    logger.info(f"📩 CHUNK RECEIVED")
    logger.info(f"   From: {chunk.sender}")
    logger.info(f"   Message ID: {msg_id[:8]}...")
    logger.info(f"   Chunk: {index}/{total or '?'}")
    logger.info(f"   Payload: {payload[:50]}{'...' if len(payload) > 50 else ''}")
    
    # Create buffer entry if new message
    if msg_id not in chunk_buffer:
        chunk_buffer[msg_id] = PartialMessage(
            msg_id=msg_id,
            sender=chunk.sender,
            timestamp=chunk.timestamp
        )
        logger.info(f"   📂 New message buffer created")
    
    # Add chunk to buffer
    chunk_buffer[msg_id].add_chunk(index, total, payload)
    
    current_count = len(chunk_buffer[msg_id].chunks)
    total_count = chunk_buffer[msg_id].max_chunks
    
    # Visual progress bar
    progress = int((current_count / total_count) * 20)
    progress_bar = "█" * progress + "░" * (20 - progress)
    logger.info(f"   [{progress_bar}] {current_count}/{total_count} chunks")
    
    # Check if message is complete
    if chunk_buffer[msg_id].is_complete:
        full_text = chunk_buffer[msg_id].merge()
        sender = chunk_buffer[msg_id].sender
        timestamp = chunk_buffer[msg_id].timestamp
        
        logger.info("=" * 50)
        logger.info(f"✅ MESSAGE COMPLETE!")
        logger.info(f"   ID: {msg_id[:8]}...")
        logger.info(f"   Length: {len(full_text)} chars")
        logger.info(f"   Content: {full_text[:100]}{'...' if len(full_text) > 100 else ''}")
        logger.info("=" * 50)
        logger.info("🚀 Sending to Ollama for processing...")
        
        # Clean up buffer
        del chunk_buffer[msg_id]
        
        # Create incoming SMS and process
        incoming = IncomingSMS(
            sender=sender,
            original_content=full_text,
            timestamp=timestamp
        )
        
        # USE THE ORIGINAL MESSAGE ID - don't generate a new hash!
        # This allows the sender to match the response to their original message
        result_hash = msg_id
        
        # Store status
        processing_status[result_hash] = "Processing"
        
        # Start background processing
        background_tasks.add_task(process_sms_background, incoming, result_hash)
        
        return {
            "message_id": msg_id,
            "is_complete": True,
            "result_hash": result_hash,  # Same as msg_id
            "status": "Processing"
        }
    
    logger.info(f"   ⏳ Waiting for {total_count - current_count} more chunk(s)...")
    logger.info("=" * 50)
    
    return {
        "message_id": msg_id,
        "is_complete": False,
        "chunks_received": current_count,
        "chunks_expected": total_count
    }

@app.post("/api/process")
async def process_sms(incoming: IncomingSMS, background_tasks: BackgroundTasks):
    """Original endpoint for processing complete messages directly."""
    # Generate a deterministic hash for this request 
    # (using sender + timestamp + content to ensure uniqueness)
    unique_str = f"{incoming.sender}|{incoming.timestamp}|{incoming.original_content}"
    result_hash = hashlib.md5(unique_str.encode()).hexdigest()
    
    # Store status
    processing_status[result_hash] = "Processing"
    
    # Start Background Task
    background_tasks.add_task(process_sms_background, incoming, result_hash)
    
    return {"hash": result_hash, "status": "Processing"}

@app.get("/api/result/{result_hash}")
async def get_result(result_hash: str):
    """Get the result of a processed message."""
    status = processing_status.get(result_hash)
    
    if not status:
        raise HTTPException(status_code=404, detail="Result not found")
        
    if status == "Processing":
        return {"status": "Processing", "message": "Result is being generated. Please wait."}
        
    if status == "Error":
         raise HTTPException(status_code=500, detail="Error during processing")
         
    if status == "Completed":
        # Return the object converted to dict, PLUS the status field
        result = results_store[result_hash].dict()
        result["status"] = "Completed"
        return result

    return {"status": "Unknown"}

@app.get("/api/buffer/status")
async def get_buffer_status():
    """Get the current status of the chunk buffer (for debugging)."""
    return {
        "pending_messages": len(chunk_buffer),
        "messages": {
            msg_id[:8]: {
                "sender": msg.sender,
                "chunks": f"{len(msg.chunks)}/{msg.max_chunks}",
                "age_seconds": (datetime.now() - msg.created_at).total_seconds()
            }
            for msg_id, msg in chunk_buffer.items()
        }
    }

