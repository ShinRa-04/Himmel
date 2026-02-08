from pydantic import BaseModel
from typing import Optional

class IncomingSMS(BaseModel):
    sender: str
    original_content: str
    timestamp: int

class IncomingChunk(BaseModel):
    """A single SMS chunk received from the server_app."""
    sender: str
    content: str  # Raw SMS content with protocol headers
    timestamp: int

class IncomingChunk(BaseModel):
    """A single SMS chunk received from the server_app."""
    sender: str
    content: str  # Raw SMS content with protocol headers
    timestamp: int

class ProcessedSMS(BaseModel):
    sender: str
    content: str
    timestamp: int
    hash: str
