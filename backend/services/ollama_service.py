import ollama

class OllamaService:
    @staticmethod
    def generate_reply(text: str, model: str = "llama3.2:1b") -> str:
        try:
            response = ollama.chat(model=model, messages=[
                {
                    'role': 'user',
                    'content': f"Answer: \"{text}\"."
                },
            ])
            return response['message']['content']
        except Exception as e:
            print(f"Error calling Ollama: {e}")
            return "Error generating response."
