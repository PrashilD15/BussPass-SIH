import asyncio
import os
import pyaudio
from google.adk.runners import Runner, LiveRequestQueue
from google.adk.sessions.in_memory_session_service import InMemorySessionService
from google.genai.types import Blob
from msrtc_human_ai_agent import get_top3_upcoming_buses

# Set your active API key via environment variable
api_key = os.environ.get('GEMINI_API_KEY', '')
if api_key:
    os.environ['GEMINI_API_KEY'] = api_key
agent = Agent(
    name="msrtc_live_agent",
    model="gemini-3.8-live", 
    instruction="""You are a friendly Helpdesk Officer for MSRTC (Pronounced 'M-S-R-T-C').
When the call starts, you MUST initiate the conversation in Hindi first, welcoming the caller to M-S-R-T-C.
In your first greeting, briefly mention that they can speak in Hindi, Marathi, or English.
Keep your answers very short, punchy, and conversational like a real human. Do not sound robotic.
If the user asks for bus timings, FIRST say something like "Please wait a moment while I check the live timetables database for you." BEFORE using the get_top3_upcoming_buses tool.
Then use the get_top3_upcoming_buses tool and read out the platform, time, and fare.""",
    tools=[get_top3_upcoming_buses]
)

runner = Runner(agent=agent, app_name="msrtc_live_app", session_service=InMemorySessionService(), auto_create_session=True)

async def audio_input(queue: LiveRequestQueue):
    """Captures microphone audio and streams it to the LiveRequestQueue."""
    p = pyaudio.PyAudio()
    stream = p.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True, frames_per_buffer=1024)
    try:
        while True:
            data = stream.read(1024, exception_on_overflow=False)
            queue.send_realtime(Blob(data=data, mime_type="audio/pcm;rate=16000"))
            await asyncio.sleep(0.01)
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()

async def audio_output(agen):
    """Reads events from the ADK Runner and plays the audio directly to speakers."""
    p = pyaudio.PyAudio()
    stream = p.open(format=pyaudio.paInt16, channels=1, rate=24000, output=True)
    try:
        async for event in agen:
            # Depending on ADK's event structure, it yields audio Blobs or content parts
            if hasattr(event, 'inline_data') and event.inline_data:
                stream.write(event.inline_data.data)
            elif hasattr(event, 'content') and event.content and getattr(event.content, 'parts', None):
                for part in event.content.parts:
                    if hasattr(part, 'inline_data') and part.inline_data:
                        stream.write(part.inline_data.data)
                    elif hasattr(part, 'text') and part.text:
                        print(f"AI Caption: {part.text}")
    finally:
        stream.stop_stream()
        stream.close()
        p.terminate()

async def main():
    queue = LiveRequestQueue()
    in_task = asyncio.create_task(audio_input(queue))
    out_task = asyncio.create_task(audio_output(runner.run_live(
        live_request_queue=queue, 
        user_id="passenger", 
        session_id="call_1"
    )))
    print("=====================================================")
    print("🎙️ MSRTC Live Voice Agent (ADK) is running!")
    print("Start speaking normally. You can interrupt the AI at any time.")
    print("=====================================================")
    await asyncio.gather(in_task, out_task)

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nCall ended.")
