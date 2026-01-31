import hashlib
import math

class ChunkCalculator:
    MAX_SMS_LENGTH = 160

    @staticmethod
    def calculate_chunk_count(full_text: str) -> int:
        if not full_text:
            return 0

        # Generate ID (MD5 Hash) - matching Dart's md5.convert(utf8.encode(text))
        msg_id = hashlib.md5(full_text.encode('utf-8')).hexdigest()

        # Naive estimation for the loop
        estimated_chunks = math.ceil(len(full_text) / 110)
        if estimated_chunks == 0:
            estimated_chunks = 1
            
        # Simulation pass (similar to Dart's dry run with 99 chunks assumption)
        dry_run_chunks = ChunkCalculator._perform_split(full_text, msg_id, 99)
        actual_total = len(dry_run_chunks)
        
        return actual_total

    @staticmethod
    def split_message(text: str, msg_id: str, total_chunks: int) -> list[str]:
        return ChunkCalculator._perform_split(text, msg_id, total_chunks)

    @staticmethod
    def _perform_split(text: str, msg_id: str, total_chunks: int) -> list[str]:
        chunks = []
        cursor = 0
        index = 1
        
        while cursor < len(text):
            # Build Header
            header = f"ID:{msg_id}\n"
            if index == 1:
                header += f"M:{total_chunks}\n"
            header += f"I:{index}\n"
            header += "T:"
            
            header_len = len(header)
            available_space = ChunkCalculator.MAX_SMS_LENGTH - header_len
            
            if available_space <= 0:
                # Should logically not happen with 160 char limit and standard MD5
                raise ValueError("Header exceeds SMS limit!")
            
            remaining_chars = len(text) - cursor
            grab = min(remaining_chars, available_space)
            
            # In Dart code: String payload = text.substring(cursor, cursor + grab);
            # Python slicing is [start:end]
            payload = text[cursor : cursor + grab]
            chunks.append(header + payload)
            
            cursor += grab
            index += 1
            
        return chunks
