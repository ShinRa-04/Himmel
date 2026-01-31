from fastapi import FastAPI, BackgroundTasks, HTTPException
from typing import Dict
import hashlib
from models import IncomingSMS, ProcessedSMS
from services.ollama_service import OllamaService

app = FastAPI()

# In-memory result store: { hash: ProcessedSMS }
results_store: Dict[str, ProcessedSMS] = {}
# Status store to distinguish between "Processing" and "Not Found"
processing_status: Dict[str, str] = {}

def process_sms_background(incoming: IncomingSMS, result_hash: str):
    """
    Background task to process the SMS with Ollama and calculate chunks.
    """
    try:
        # 1. Generate Reply
        reply_text = OllamaService.generate_reply(incoming.original_content)
        
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
        
    except Exception as e:
        print(f"Error processing SMS {result_hash}: {e}")
        processing_status[result_hash] = "Error"

@app.post("/api/process")
async def process_sms(incoming: IncomingSMS, background_tasks: BackgroundTasks):
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
