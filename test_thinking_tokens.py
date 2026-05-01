#!/usr/bin/env python3
"""
Test script to verify Ollama Cloud thinking tokens are working.
This bypasses the NyxStrike backend and talks directly to Ollama.
"""

import json
import requests
import os
import sys

# Your Ollama API key
OLLAMA_API_KEY = os.environ.get("OLLAMA_API_KEY", "a6fe38c3983c4ba5b142dfba6528cef6.k18PBm0OvXKh1opZxYKUgrEN")
OLLAMA_URL = "https://ollama.com/api/chat"
MODEL = "qwen3.5:397b-cloud"

def test_thinking_tokens():
    """Test if thinking tokens are being returned by Ollama."""
    
    print(f"Testing Ollama Cloud with model: {MODEL}")
    print(f"API Key: {OLLAMA_API_KEY[:20]}...")
    print("-" * 60)
    
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "user", "content": "What is 2+2? Think step by step."}
        ],
        "stream": True,
        "think": True,  # Enable thinking mode
    }
    
    # Try without "sk-" prefix if present
    api_key = OLLAMA_API_KEY.replace("sk-", "") if OLLAMA_API_KEY.startswith("sk-") else OLLAMA_API_KEY
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }
    
    print(f"Using API key: {api_key[:30]}...")
    
    print("\n📤 Sending request to Ollama Cloud...")
    print(f"Payload: {json.dumps(payload, indent=2)}\n")
    
    thinking_content = []
    response_content = []
    
    try:
        with requests.post(OLLAMA_URL, json=payload, headers=headers, stream=True, timeout=60) as resp:
            if resp.status_code != 200:
                print(f"❌ Error: HTTP {resp.status_code}")
                print(f"Response: {resp.text}")
                return False
            
            print("✅ Connected! Streaming response...\n")
            print("=" * 60)
            
            for line in resp.iter_lines():
                if not line:
                    continue
                
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                
                msg = data.get("message", {})
                
                # Check for thinking tokens
                thinking = msg.get("thinking", "")
                if thinking:
                    thinking_content.append(thinking)
                    print(f"🧠 THINKING: {thinking}", end="", flush=True)
                
                # Check for content tokens
                content = msg.get("content", "")
                if content:
                    response_content.append(content)
                    print(f"💬 CONTENT: {content}", end="", flush=True)
                
                # Check if done
                if data.get("done"):
                    print("\n\n✅ Stream completed!")
                    print("=" * 60)
                    
                    # Print summary
                    thinking_text = "".join(thinking_content)
                    response_text = "".join(response_content)
                    
                    print("\n📊 Summary:")
                    print(f"  Thinking tokens: {len(thinking_content)}")
                    print(f"  Content tokens: {len(response_content)}")
                    print(f"\n🧠 Full thinking process ({len(thinking_text)} chars):")
                    print("-" * 60)
                    print(thinking_text[:500] + ("..." if len(thinking_text) > 500 else ""))
                    print("-" * 60)
                    print(f"\n💬 Final answer ({len(response_text)} chars):")
                    print("-" * 60)
                    print(response_text)
                    print("-" * 60)
                    
                    # Check results
                    if thinking_content:
                        print("\n✅ SUCCESS: Thinking tokens ARE being returned!")
                        return True
                    else:
                        print("\n⚠️  WARNING: No thinking tokens received (model may not support it)")
                        return False
            
    except requests.exceptions.Timeout:
        print("❌ Request timed out")
        return False
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Connection error: {e}")
        return False
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_thinking_tokens()
    sys.exit(0 if success else 1)
