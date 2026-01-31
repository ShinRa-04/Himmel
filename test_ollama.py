import ollama

def test_ollama():
    try:
        print("Testing Ollama with model 'gemma3:4b'...")
        response = ollama.chat(model='gemma3:4b', messages=[
            {
                'role': 'user',
                'content': 'Hello! Are you working?',
            },
        ])
        print("\nResponse received:")
        print(response['message']['content'])
    except Exception as e:
        print(f"\nError: {e}")
        print("Make sure Ollama is running and you have pulled the model (e.g., 'ollama pull gemma2:4b').")

if __name__ == "__main__":
    test_ollama()
