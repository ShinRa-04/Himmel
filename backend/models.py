from pydantic import BaseModel
from typing import Optional

class IncomingSMS(BaseModel):
    sender: str
    original_content: str
    timestamp: int

class ProcessedSMS(BaseModel):
    sender: str
    content: str
    timestamp: int
    hash: str
