import requests, sys, os
api_key = os.environ.get('GEMINI_API_KEY', '')
url = f'https://generativelanguage.googleapis.com/v1beta/models?key={api_key}'
try:
    res = requests.get(url)
    models = [m['name'].split('/')[-1] for m in res.json().get('models', [])]
    
    for m in models:
        test_url = f'https://generativelanguage.googleapis.com/v1beta/models/{m}:generateContent?key={api_key}'
        payload = {
            'contents': [{"role": "user", "parts": [{"text": "hello"}]}],
            'systemInstruction': {'parts': [{'text': "You are an AI"}]}
        }
        try:
            r = requests.post(test_url, json=payload, timeout=2)
            if r.status_code == 200:
                print(f"WORKING MODEL FOUND: {m}")
                sys.exit(0)
        except Exception:
            pass
    print("NO WORKING MODELS FOUND")
except Exception as e:
    print(e)
