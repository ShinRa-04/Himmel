import ollama

class OllamaService:
    @staticmethod
    def generate_reply(text: str, model: str = "gemma3:4b") -> str:
        try:
            response = ollama.chat(model=model, messages=[
                {
                    'role': 'user',
                    'content': f"Reply to this SMS message: \"{text}\". Keep it concise and natural."
                },
            ])
            return response['message']['content']
        except Exception as e:
            print(f"Error calling Ollama: {e}")
            return "Error generating response."
