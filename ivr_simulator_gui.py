# -*- coding: utf-8 -*-
import sys
import os
import json
import time
import datetime
import asyncio
import threading
import subprocess
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import pyaudio
from google.adk import Agent
from google.adk.runners import Runner, LiveRequestQueue
from google.adk.sessions.in_memory_session_service import InMemorySessionService
from google.genai.types import Blob, Content, Part
import wave
import datetime

import os
api_key = os.environ.get('GEMINI_API_KEY', '')
if api_key:
    os.environ['GEMINI_API_KEY'] = api_key

# Import all tools and the agent instruction from the core agent module
from msrtc_human_ai_agent import (
    get_caller_profile,
    update_caller_profile,
    get_top3_upcoming_buses,
    get_route_details,
    get_fare_details,
    get_live_bus_eta,
    get_caller_ticket,
    handle_emergency,
    MSRTC_AGENT_INSTRUCTION,
    HAS_FIREBASE,
    db
)


class IVRSimulatorGUI:
    def __init__(self, root):
        self.root = root
        self.root.title('BussPass IVR System Simulator - MSRTC Enquiry Officer AI (SIH 2026)')
        self.root.geometry('1060x720')
        self.root.configure(bg='#0f111a')
        self.is_call_active = False
        self.call_start_time = 0
        self.selected_language = 'ENGLISH'
        self.caller_phone = '+919876543210'
        self.ticket_data = {}
        self.chat_history = []
        self.gemini_api_key = os.environ.get('GEMINI_API_KEY', '')
        self.load_audio_devices()
        self.setup_styles()
        self.build_ui()
        self.update_call_timer()
        self.start_iot_listener()

    def start_iot_listener(self):
        if HAS_FIREBASE:
            self.log_msg('FIRESTORE', '📡 Starting IoT Hardware Listener (ivr_gateway/current_call)...')
            doc_ref = db.collection('ivr_gateway').document('current_call')
            
            def on_snapshot(doc_snapshot, changes, read_time):
                for doc in doc_snapshot:
                    if doc.exists:
                        data = doc.to_dict()
                        if data.get('status') == 'ringing':
                            caller = data.get('phone', '+919876543210')
                            self.root.after(0, self.handle_incoming_iot_call, caller)
                            # Reset status to 'answered' to prevent loops
                            doc_ref.update({'status': 'answered'})
                            
            self.iot_watch = doc_ref.on_snapshot(on_snapshot)
        else:
            self.log_msg('SYSTEM', '⚠️ Firebase not connected. IoT listener disabled.')

    def handle_incoming_iot_call(self, caller_phone):
        if self.is_call_active:
            return
        self.log_msg('SYSTEM', f'🔔 IOT TRIGGER: Incoming call from {caller_phone}')
        self.entry_phone.delete(0, tk.END)
        self.entry_phone.insert(0, caller_phone)
        self.start_call()

    def load_audio_devices(self):
        p = pyaudio.PyAudio()
        self.input_devices = ['Default Mac Input']
        self.output_devices = ['Default Mac Output']
        self.input_device_indices = [None]
        self.output_device_indices = [None]
        
        for i in range(p.get_device_count()):
            info = p.get_device_info_by_index(i)
            name = info.get('name', f'Device {i}')
            if info.get('maxInputChannels', 0) > 0:
                self.input_devices.append(f"[{i}] {name}")
                self.input_device_indices.append(i)
            if info.get('maxOutputChannels', 0) > 0:
                self.output_devices.append(f"[{i}] {name}")
                self.output_device_indices.append(i)
        p.terminate()

    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('default')
        style.configure('.', background='#0f111a', foreground='#ffffff')

    def build_ui(self):
        header = tk.Frame(self.root, bg='#1a1d2e', height=65, relief='raised', bd=1)
        header.pack(fill='x', side='top')
        lbl_title = tk.Label(header, text='BUSSPASS MSRTC HELP DESK AI SIMULATOR', font=('Helvetica', 15, 'bold'), bg='#1a1d2e', fg='#70a1ff')
        lbl_title.pack(side='left', padx=15, pady=10)

        main_container = tk.Frame(self.root, bg='#0f111a')
        main_container.pack(fill='both', expand=True, padx=15, pady=15)

        left_panel = tk.Frame(main_container, bg='#16192b', width=380, bd=1, relief='solid')
        left_panel.pack(side='left', fill='y', padx=(0, 15))
        left_panel.pack_propagate(False)

        screen_frame = tk.Frame(left_panel, bg='#0a0c14', bd=2, relief='sunken')
        screen_frame.pack(fill='x', padx=15, pady=12)

        self.lbl_status = tk.Label(screen_frame, text='IDLE / READY', font=('Helvetica', 11, 'bold'), bg='#0a0c14', fg='#a4b0be')
        self.lbl_status.pack(pady=(10, 2))

        self.lbl_timer = tk.Label(screen_frame, text='00:00', font=('Consolas', 22, 'bold'), bg='#0a0c14', fg='#2ed573')
        self.lbl_timer.pack(pady=2)

        phone_box = tk.Frame(screen_frame, bg='#0a0c14')
        phone_box.pack(pady=(4, 10))
        tk.Label(phone_box, text='Caller ID:', font=('Helvetica', 9), bg='#0a0c14', fg='#747d8c').pack(side='left', padx=5)
        self.entry_phone = tk.Entry(phone_box, font=('Consolas', 12, 'bold'), bg='#1e2238', fg='#ffffff', width=15, justify='center')
        self.entry_phone.insert(0, '+919876543210')
        self.entry_phone.pack(side='left')

        self.lbl_lang_banner = tk.Label(left_panel, text='LANGUAGE: NOT SELECTED', font=('Helvetica', 10, 'bold'), bg='#2f3542', fg='#ffa502', pady=6)
        self.lbl_lang_banner.pack(fill='x', padx=15, pady=(0, 8))

        btn_box = tk.Frame(left_panel, bg='#16192b')
        btn_box.pack(fill='x', padx=15, pady=4)

        self.btn_call = tk.Button(btn_box, text="DIAL CALL", font=('Helvetica', 11, 'bold'), bg='#2ed573', fg='#ffffff', bd=0, pady=8, command=self.start_call)
        self.btn_call.pack(side='left', fill='x', expand=True, padx=(0, 5))

        self.btn_hangup = tk.Button(btn_box, text='HANG UP', font=('Helvetica', 11, 'bold'), bg='#ff4757', fg='#ffffff', bd=0, pady=8, state='disabled', command=self.end_call)
        self.btn_hangup.pack(side='right', fill='x', expand=True, padx=(5, 0))

        tk.Label(left_panel, text='DTMF Phone Keypad', font=('Helvetica', 10, 'bold'), bg='#16192b', fg='#a4b0be').pack(pady=(10, 4))

        keypad_frame = tk.Frame(left_panel, bg='#16192b')
        keypad_frame.pack(padx=15, pady=4)

        keys = [
            [('1\nHindi', '1'), ('2\nMarathi', '2'), ('3\nEnglish', '3')],
            [('4\nTrack', '4'), ('5\nTicket', '5'), ('6\nHelp', '6')],
            [('7', '7'), ('8', '8'), ('9', '9')],
            [('*', '*'), ('0', '0'), ('#', '#')]
        ]

        for r, row in enumerate(keys):
            for c, (label, val) in enumerate(row):
                btn = tk.Button(keypad_frame, text=label, font=('Helvetica', 9, 'bold'), bg='#2f3542', fg='#ffffff', activebackground='#70a1ff', width=9, height=2, bd=1, command=lambda v=val: self.press_dtmf(v))
                btn.grid(row=r, column=c, padx=3, pady=3)

        audio_frame = tk.Frame(left_panel, bg='#16192b')
        audio_frame.pack(fill='x', padx=15, pady=10)
        
        tk.Label(audio_frame, text='Audio Input (Mic):', bg='#16192b', fg='#a4b0be', font=('Helvetica', 9, 'bold')).pack(anchor='w')
        self.combo_mic = ttk.Combobox(audio_frame, values=self.input_devices, state='readonly', font=('Helvetica', 9))
        self.combo_mic.current(0)
        self.combo_mic.pack(fill='x', pady=(2, 8))

        tk.Label(audio_frame, text='Audio Output (Spk):', bg='#16192b', fg='#a4b0be', font=('Helvetica', 9, 'bold')).pack(anchor='w')
        self.combo_spk = ttk.Combobox(audio_frame, values=self.output_devices, state='readonly', font=('Helvetica', 9))
        self.combo_spk.current(0)
        self.combo_spk.pack(fill='x', pady=(2, 0))

        right_panel = tk.Frame(main_container, bg='#16192b', bd=1, relief='solid')
        right_panel.pack(side='right', fill='both', expand=True)

        log_header = tk.Frame(right_panel, bg='#1e2238', pady=8)
        log_header.pack(fill='x')
        tk.Label(log_header, text='ST Helpdesk Officer - Conversation Transcript', font=('Helvetica', 11, 'bold'), bg='#1e2238', fg='#70a1ff').pack(side='left', padx=15)

        self.txt_log = scrolledtext.ScrolledText(right_panel, font=('Consolas', 10), bg='#0a0c14', fg='#70a1ff', bd=0, padx=12, pady=12)
        self.txt_log.pack(fill='both', expand=True, padx=12, pady=12)

        self.txt_log.tag_config('SYSTEM', foreground='#a4b0be')
        self.txt_log.tag_config('CALLER', foreground='#eccc68', font=('Consolas', 10, 'bold'))
        self.txt_log.tag_config('AI', foreground='#2ed573', font=('Consolas', 10, 'bold'))
        self.txt_log.tag_config('FIRESTORE', foreground='#70a1ff', font=('Consolas', 9, 'italic'))
        self.txt_log.tag_config('DTMF', foreground='#ff6b81', font=('Consolas', 10, 'bold'))

        speech_box = tk.Frame(right_panel, bg='#1e2238', pady=10, padx=12)
        speech_box.pack(fill='x', side='bottom')

        tk.Label(speech_box, text='Passenger Input:', font=('Helvetica', 10, 'bold'), bg='#1e2238', fg='#ffffff').pack(side='left', padx=(0, 8))

        self.entry_speech = tk.Entry(speech_box, font=('Helvetica', 11), bg='#0a0c14', fg='#ffffff', insertbackground='white')
        self.entry_speech.pack(side='left', fill='x', expand=True, padx=(0, 8))
        self.entry_speech.bind('<Return>', lambda e: self.send_speech_text())

        btn_send_speech = tk.Button(speech_box, text='SEND', font=('Helvetica', 10, 'bold'), bg='#70a1ff', fg='#1e1e2e', command=self.send_speech_text)
        btn_send_speech.pack(side='right', padx=(4, 0))

        btn_mic_listen = tk.Button(speech_box, text='LISTEN MIC (12s)', font=('Helvetica', 10, 'bold'), bg='#ff6b81', fg='#ffffff', command=self.listen_from_mic)
        btn_mic_listen.pack(side='right', padx=4)

        self.log_msg('SYSTEM', '==================================================')
        self.log_msg('SYSTEM', '  BussPass MSRTC AI Helpdesk v2.0 - CRM Edition  ')
        self.log_msg('SYSTEM', '  Tools: Caller CRM | Routes | Fares | Stops      ')
        self.log_msg('SYSTEM', '         Emergency | Live Track | Ticket Lookup    ')
        self.log_msg('SYSTEM', '  DB: Firestore Routes:75 | Stops:53 | Fares:75   ')
        self.log_msg('SYSTEM', '==================================================')
        self.log_msg('SYSTEM', 'Click [DIAL CALL] on the left to start testing!')

    def log_msg(self, tag, text):
        timestamp = time.strftime('[%H:%M:%S] ')
        self.txt_log.insert(tk.END, timestamp, 'SYSTEM')
        self.txt_log.insert(tk.END, text + '\n', tag)
        self.txt_log.see(tk.END)



    def update_call_timer(self):
        if self.is_call_active:
            elapsed = int(time.time() - self.call_start_time)
            mins = elapsed // 60
            secs = elapsed % 60
            self.lbl_timer.config(text=f'{mins:02d}:{secs:02d}')
        self.root.after(1000, self.update_call_timer)

    def start_call(self):
        self.caller_phone = self.entry_phone.get().strip()
        if not self.caller_phone:
            messagebox.showwarning('Warning', 'Please enter a valid phone number!')
            return

        self.is_call_active = True
        self.call_start_time = time.time()
        self.chat_history = []
        self.selected_language = 'NOT SELECTED'
        
        self.call_id = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        self.caller_frames = []
        self.ai_frames = []

        self.btn_call.config(state='disabled', bg='#747d8c')
        self.btn_hangup.config(state='normal', bg='#ff4757')
        self.lbl_status.config(text='CALL CONNECTED', fg='#2ed573')
        self.lbl_lang_banner.config(text='PRESS 1: HINDI | 2: MARATHI | 3: ENGLISH', bg='#ffa502', fg='#1e1e2e')

        self.log_msg('SYSTEM', f'Incoming call connected from: {self.caller_phone}')

        threading.Thread(target=self.run_adk_live, daemon=True).start()

    def run_adk_live(self):
        self.ai_ready = False
        threading.Thread(target=self.play_ringing_tone, daemon=True).start()
        
        # Phase 0: Pre-fetch caller profile from Firestore (in background thread so UI doesn't freeze)
        self.root.after(0, self.log_msg, 'FIRESTORE', f'Fetching caller profile for: {self.caller_phone}...')
        try:
            caller_profile = get_caller_profile(self.caller_phone)
            if caller_profile.get('is_new_caller'):
                self.root.after(0, self.log_msg, 'FIRESTORE', f'New caller — no profile found. AI will ask for name.')
            else:
                name = caller_profile.get('name', 'Unknown')
                lang = caller_profile.get('preferred_language', 'HINDI')
                calls = caller_profile.get('total_calls', 0)
                self.root.after(0, self.log_msg, 'FIRESTORE', f'Returning caller: {name} | Lang: {lang} | Total calls: {calls}')
                last_q = caller_profile.get('last_query', '')
                if last_q:
                    self.root.after(0, self.log_msg, 'FIRESTORE', f'Last query: "{last_q}"')

            # Pre-fetch ticket if available
            ticket_data = get_caller_ticket(self.caller_phone)
            if ticket_data.get('found'):
                self.root.after(0, self.log_msg, 'FIRESTORE', f'Active Ticket: Bus {ticket_data.get("bus_number")} ({ticket_data.get("route", "")})')
            else:
                self.root.after(0, self.log_msg, 'FIRESTORE', 'No active ticket found for this caller.')
        except Exception as e:
            self.root.after(0, self.log_msg, 'FIRESTORE', f'Warning: CRM Fetch error: {e}')

        self.root.after(0, self.log_msg, 'SYSTEM', 'Starting Gemini Live Voice Connection (ADK)...')
        try:
            asyncio.run(self.adk_main())
        except Exception as e:
            self.root.after(0, self.log_msg, 'SYSTEM', f'ADK Live Error: {e}')

    async def adk_main(self):
        # Full CRM-powered agent with all 8 tools
        agent = Agent(
            name="msrtc_live_agent",
            model="gemini-3.8-live",
            instruction=MSRTC_AGENT_INSTRUCTION,
            tools=[
                get_caller_profile,
                update_caller_profile,
                get_top3_upcoming_buses,
                get_route_details,
                get_fare_details,
                get_live_bus_eta,
                get_caller_ticket,
                handle_emergency,
            ],
            generate_content_config={
                "response_modalities": ["AUDIO", "TEXT"],
                "speech_config": {
                    "voice_config": {
                        "prebuilt_voice_config": {
                            "voice_name": "Aoede"
                        }
                    }
                }
            }
        )
        runner = Runner(agent=agent, app_name="msrtc_live_app", session_service=InMemorySessionService(), auto_create_session=True)
        queue = LiveRequestQueue()
        
        # Force the AI to speak first by injecting a system prompt into the connection queue
        queue.send_content(Content(parts=[Part(text="[SYSTEM: The phone call has just connected. You must immediately greet the caller warmly and ask how you can help them today.]")]))
        
        self.ai_ready = True
        
        in_task = asyncio.create_task(self.audio_input(queue))
        out_task = asyncio.create_task(self.audio_output(runner.run_live(
            live_request_queue=queue,
            user_id="passenger",
            session_id=str(time.time())
        )))
        
        try:
            await asyncio.gather(in_task, out_task)
        except Exception as e:
            self.is_call_active = False # Ensures everything gracefully terminates
            in_task.cancel()
            out_task.cancel()
            raise e

    def play_ringing_tone(self):
        import math, struct
        p = None
        stream = None
        try:
            out_idx = self.combo_spk.current()
            out_device = self.output_device_indices[out_idx]
            p = pyaudio.PyAudio()
            stream = p.open(format=pyaudio.paFloat32, channels=1, rate=16000, output=True, output_device_index=out_device)
            t = 0.0
            while self.is_call_active and not getattr(self, 'ai_ready', False):
                samples = []
                # Standard Indian/European Ringtone: 1s ON, 2s OFF (400Hz + 425Hz)
                for _ in range(1600):
                    if (t % 3.0) < 1.0:
                        sample = 0.3 * math.sin(2 * math.pi * 400 * t) + 0.3 * math.sin(2 * math.pi * 425 * t)
                    else:
                        sample = 0.0
                    samples.append(sample)
                    t += 1.0 / 16000
                buf = struct.pack('f' * len(samples), *samples)
                stream.write(buf)
        except Exception as e:
            pass
        finally:
            if stream:
                stream.stop_stream()
                stream.close()
            if p:
                p.terminate()

    async def audio_input(self, queue):
        p = None
        stream = None
        try:
            in_idx = self.combo_mic.current()
            in_device = self.input_device_indices[in_idx]
            p = pyaudio.PyAudio()
            stream = p.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True, frames_per_buffer=1024, input_device_index=in_device)
            while self.is_call_active:
                data = await asyncio.to_thread(stream.read, 1024, exception_on_overflow=False)
                if hasattr(self, 'caller_frames'):
                    self.caller_frames.append(data)
                
                if not getattr(self, 'is_ai_speaking', False):
                    queue.send_realtime(Blob(data=data, mime_type="audio/pcm;rate=16000"))
                await asyncio.sleep(0.005)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            self.root.after(0, self.log_msg, 'SYSTEM', f'Audio In Error: {e}')
        finally:
            if stream:
                stream.stop_stream()
                stream.close()
            if p:
                p.terminate()

    async def audio_output(self, agen):
        p = None
        stream = None
        try:
            out_idx = self.combo_spk.current()
            out_device = self.output_device_indices[out_idx]
            p = pyaudio.PyAudio()
            stream = p.open(format=pyaudio.paInt16, channels=1, rate=24000, output=True, output_device_index=out_device)
            async for event in agen:
                if not self.is_call_active:
                    break
                
                try:
                    if hasattr(event, 'inline_data') and event.inline_data:
                        self.is_ai_speaking = True
                        if hasattr(self, 'ai_frames'):
                            self.ai_frames.append(event.inline_data.data)
                        await asyncio.to_thread(stream.write, event.inline_data.data)
                        self.is_ai_speaking = False
                    elif hasattr(event, 'content') and event.content and getattr(event.content, 'parts', None):
                        for part in event.content.parts:
                            if hasattr(part, 'inline_data') and part.inline_data:
                                self.is_ai_speaking = True
                                if hasattr(self, 'ai_frames'):
                                    self.ai_frames.append(part.inline_data.data)
                                await asyncio.to_thread(stream.write, part.inline_data.data)
                                self.is_ai_speaking = False
                            elif hasattr(part, 'text') and part.text:
                                self.root.after(0, self.log_msg, 'AI', part.text)
                except Exception as e:
                    self.is_ai_speaking = False
                    self.root.after(0, self.log_msg, 'SYSTEM', f'Audio write error: {e}')
        except asyncio.CancelledError:
            pass
        except Exception as e:
            self.root.after(0, self.log_msg, 'SYSTEM', f'Audio Out Error: {e}')
        finally:
            if stream:
                stream.stop_stream()
                stream.close()
            if p:
                p.terminate()

    def end_call(self):
        self.is_call_active = False
        self.btn_call.config(state='normal', bg='#2ed573')
        self.btn_hangup.config(state='disabled', bg='#747d8c')
        self.lbl_status.config(text='IDLE / READY', fg='#a4b0be')
        self.lbl_timer.config(text='00:00')
        self.lbl_lang_banner.config(text='LANGUAGE: NOT SELECTED', bg='#2f3542', fg='#ffa502')
        self.log_msg('SYSTEM', 'Call ended by passenger.')
        self.root.after(1000, self.save_recordings)

    def save_recordings(self):
        try:
            if hasattr(self, 'caller_frames') and self.caller_frames:
                filename = f"call_{self.call_id}_caller_input.wav"
                with wave.open(filename, 'wb') as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2)
                    wf.setframerate(16000)
                    wf.writeframes(b''.join(self.caller_frames))
                self.log_msg('SYSTEM', f'💾 Caller audio saved to {filename}')
            
            if hasattr(self, 'ai_frames') and self.ai_frames:
                filename = f"call_{self.call_id}_ai_output.wav"
                with wave.open(filename, 'wb') as wf:
                    wf.setnchannels(1)
                    wf.setsampwidth(2)
                    wf.setframerate(24000)
                    wf.writeframes(b''.join(self.ai_frames))
                self.log_msg('SYSTEM', f'💾 AI audio saved to {filename}')
        except Exception as e:
            self.log_msg('SYSTEM', f'⚠️ Failed to save recordings: {e}')

    def press_dtmf(self, val):
        if not self.is_call_active:
            self.log_msg('SYSTEM', "Please click DIAL CALL first!")
            return

        self.log_msg('DTMF', f'Keypad Button Pressed: [{val}]')

        if val == '1':
            self.selected_language = 'HINDI'
            self.lbl_lang_banner.config(text='LANGUAGE: HINDI (Hindi)', bg='#2ed573', fg='#1e1e2e')
            msg = 'Namaskar! MSRTC Helpdesk Inquiry Counter me aapka swagat hai. Main aapki kya madad kar sakta hoon?'
            self.speak_ai_response(msg, voice='hi-IN-SwaraNeural')

        elif val == '2':
            self.selected_language = 'MARATHI'
            self.lbl_lang_banner.config(text='LANGUAGE: MARATHI (Marathi)', bg='#70a1ff', fg='#1e1e2e')
            msg = 'Namaskar! MSRTC State Transport Inquiry counter var tumche swagat aahe. Me tumchi kay madat karu shakto?'
            self.speak_ai_response(msg, voice='mr-IN-AarohiNeural')

        elif val == '3':
            self.selected_language = 'ENGLISH'
            self.lbl_lang_banner.config(text='LANGUAGE: ENGLISH', bg='#eccc68', fg='#1e1e2e')
            msg = 'Hello! Welcome to MSRTC State Transport Enquiry Counter. How can I help you with your journey today?'
            self.speak_ai_response(msg, voice='en-IN-NeerjaNeural')

        elif val == '4':
            bus_no = self.ticket_data.get('bus_number', 'MH-12-AB-1234')
            eta_info = get_live_bus_eta(bus_no)
            resp = f'Bus {bus_no} is currently near {eta_info["current_location"]}. Boarding at {self.ticket_data.get("boarding_stand")} arriving in {eta_info["eta_minutes"]} minutes.'
            self.speak_ai_response(resp)

    def listen_from_mic(self):
        if not self.is_call_active:
            messagebox.showwarning('Call Not Active', 'Please click DIAL CALL first!')
            return

        if not HAS_SR:
            messagebox.showerror('Error', 'SpeechRecognition module not found!')
            return

        def _record():
            try:
                self.log_msg('SYSTEM', 'Listening to laptop microphone (speak clearly for up to 12s)...')
                r = sr.Recognizer()
                with sr.Microphone() as source:
                    r.adjust_for_ambient_noise(source, duration=0.8)
                    audio_data = r.listen(source, timeout=8, phrase_time_limit=12)
                
                self.log_msg('SYSTEM', 'Processing voice...')
                lang_code = 'en-IN'
                if self.selected_language == 'HINDI':
                    lang_code = 'hi-IN'
                elif self.selected_language == 'MARATHI':
                    lang_code = 'mr-IN'

                text = r.recognize_google(audio_data, language=lang_code)
                self.log_msg('CALLER', f'Passenger (Spoken): "{text}"')
                self.process_ai_query(text)
            except sr.WaitTimeoutError:
                self.log_msg('SYSTEM', 'No speech detected (Timeout).')
            except sr.UnknownValueError:
                self.log_msg('SYSTEM', 'Could not understand audio.')
            except Exception as e:
                self.log_msg('SYSTEM', f'Mic Error: {e}')

        threading.Thread(target=_record, daemon=True).start()

    def send_speech_text(self):
        text = self.entry_speech.get().strip()
        if not text:
            return
        if not self.is_call_active:
            messagebox.showwarning('Call Not Active', 'Please click DIAL CALL first!')
            return

        self.entry_speech.delete(0, tk.END)
        self.log_msg('CALLER', f'Passenger: "{text}"')
        threading.Thread(target=self.process_ai_query, args=(text,), daemon=True).start()

    def process_ai_query(self, user_text):
        self.log_msg('SYSTEM', 'MSRTC Enquiry Officer AI analyzing intent & searching timetables...')
        
        query_lower = user_text.lower()
        
        # 1. Local Intent Classification (to fetch correct context)
        intent = 'UNKNOWN'
        
        # Language Switch Intent
        if any(w in query_lower for w in ['hindi', 'marathi', 'english', 'bhasha', 'language', 'vartalap']):
            intent = 'LANGUAGE_SWITCH'
            if 'hindi' in query_lower:
                self.selected_language = 'HINDI'
            elif 'marathi' in query_lower:
                self.selected_language = 'MARATHI'
            elif 'english' in query_lower:
                self.selected_language = 'ENGLISH'
            self.lbl_lang_banner.config(text=f'LANGUAGE: {self.selected_language}', bg='#2ed573', fg='#1e1e2e')
                
        # Booking Request Intent (Guardrail)
        elif any(w in query_lower for w in ['book', 'booking', 'ticket chahiye', 'ticket pahije', 'reserve']):
            intent = 'BOOKING_REQUEST'
            
        # Journey Plan Intent
        elif any(w in query_lower for w in ['jaana hai', 'jayche aahe', 'kab milegi', 'bus kab', 'kiti vajta', 'vel', 'want to go', 'timing', 'schedule', 'nashik', 'pune', 'mumbai', 'sangamner']):
            intent = 'JOURNEY_PLAN'
            
        # Bus Tracking Intent
        elif any(w in query_lower for w in ['kahan hai', 'kidhar hai', 'live location', 'status', 'kuthe aahe', 'where is', 'track']):
            intent = 'BUS_TRACKING'
            
        self.log_msg('SYSTEM', f'Intent Detected: {intent}')
        
        voice = 'en-IN-NeerjaNeural'
        if self.selected_language == 'MARATHI':
            voice = 'mr-IN-AarohiNeural'
        elif self.selected_language == 'HINDI':
            voice = 'hi-IN-SwaraNeural'
            
        # 2. Fetch Relevant Context
        context_data = "No specific context needed."
        if intent == 'JOURNEY_PLAN':
            upcoming_buses = get_top3_upcoming_buses('', user_text)
            if not upcoming_buses:
                words = user_text.lower().split()
                for w in words:
                    if len(w) > 3 and w not in ['bus', 'kahan', 'kuth', 'time', 'kab', 'kashi', 'jana', 'jaye']:
                        found = get_top3_upcoming_buses('', w)
                        if found:
                            upcoming_buses.extend(found)
                            break
            context_data = f"Top 3 Upcoming Buses: {json.dumps(upcoming_buses[:3])}" if upcoming_buses else "No upcoming buses found for this route."
        elif intent == 'BUS_TRACKING':
            bus_no = self.ticket_data.get('bus_number', 'MH-12-AB-1234')
            eta_data = get_live_bus_eta(bus_no)
            context_data = f"Live Bus Data: {json.dumps(eta_data)}"
            
        # 3. Call Gemini AI (Primary Engine)
        ai_reply = ''
        if self.gemini_api_key:
            now_time_str = datetime.datetime.now().strftime('%I:%M %p')
            system_instruction = f"""
You are a warm, empathetic, human State Transport Enquiry Helpdesk Officer (MSRTC) sitting at a physical bus stand inquiry counter.
Current Time: {now_time_str}
Caller Language: {self.selected_language}
Caller Phone: {self.caller_phone}

DETECTED INTENT: {intent}
CONTEXT DATA FROM DATABASE:
{context_data}

PERSONA & RESPONSE RULES (CRITICAL):
1. ALWAYS acknowledge the caller's query FIRST naturally.
2. Respond strictly in {self.selected_language}.
3. Keep the tone very respectful and helpful.
4. GUARDRAIL - IF TICKET BOOKING: Reject politely and say ticket booking is ONLY available at the nearest MSRTC Depot or the official MSRTC App.
5. IF JOURNEY PLAN: Provide exact Boarding Platform, Deboarding Stand, Departure Time, Bus Type, AND Ticket Price from the CONTEXT DATA.
6. IF BUS TRACKING: Provide current location and ETA from CONTEXT DATA.
7. ASK FOLLOW-UP: End your response by asking a follow-up question (e.g. "Do you want me to track this bus?" or "Shall I provide details for the next bus?") to maintain a conversational flow.
"""
            self.chat_history.append({"role": "user", "parts": [{"text": user_text}]})
            try:
                import requests
                url = f'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key={self.gemini_api_key}'
                payload = {
                    'contents': self.chat_history,
                    'systemInstruction': {'parts': [{'text': system_instruction}]}
                }
                res = requests.post(url, json=payload, timeout=8)
                if res.status_code == 200:
                    data = res.json()
                    ai_reply = data['candidates'][0]['content']['parts'][0]['text'].strip()
                    self.chat_history.append({"role": "model", "parts": [{"text": ai_reply}]})
            except Exception as e:
                self.log_msg('SYSTEM', f'Gemini REST error: {e}')
                if self.chat_history:
                    self.chat_history.pop()
                
        # 4. Fallback (Only if API fails)
        if not ai_reply:
            self.log_msg('SYSTEM', 'WARNING: AI Model failed, falling back to basic responses.')
            if intent == 'LANGUAGE_SWITCH':
                if self.selected_language == 'HINDI':
                    ai_reply = 'Thik hai, ab hum Hindi mein baat karenge. Main aapki kya madad kar sakti hoon?'
                elif self.selected_language == 'MARATHI':
                    ai_reply = 'Theek aahe, aapan aataa Marathi madhe bolu. Me tumchi kay madat karu shakte?'
                else:
                    ai_reply = 'Alright, we will speak in English now. How can I help you today?'
            elif intent == 'BOOKING_REQUEST':
                if self.selected_language == 'HINDI':
                    ai_reply = 'Maaf kijiye, ticket booking is helpline par uplabdh nahi hai. Aap apne nazdiki MSRTC depot ya official app par ticket book kar sakte hain.'
                elif self.selected_language == 'MARATHI':
                    ai_reply = 'Kshamasva, ticket booking ya helpline var uplabdh nahi. Tumhi javil MSRTC depot kinva official app var ticket book karu shakta.'
                else:
                    ai_reply = 'Sorry, ticket booking is not available on this helpline. You can book tickets at the nearest MSRTC depot or the official app.'
            elif intent == 'JOURNEY_PLAN' and 'upcoming_buses' in locals() and upcoming_buses:
                bus_info = upcoming_buses[0]
                if self.selected_language == 'HINDI':
                    ai_reply = f'Maine samjha, aap {bus_info["destination"]} jana chahte hain. Agli bus {bus_info["time"]} {bus_info["boarding_platform"]} se niklegi. Yeh {bus_info["bus_type"]} bus hai.'
                elif self.selected_language == 'MARATHI':
                    ai_reply = f'Me samajalo, tumhala {bus_info["destination"]} la jayche aahe. Pudhchi bus {bus_info["time"]} la {bus_info["boarding_platform"]} varun sutel. Hi {bus_info["bus_type"]} bus aahe.'
                else:
                    ai_reply = f'I understand you want to go to {bus_info["destination"]}. The next bus departs at {bus_info["time"]} from {bus_info["boarding_platform"]}. It is a {bus_info["bus_type"]} bus.'
            elif intent == 'BUS_TRACKING' and 'eta_data' in locals():
                if self.selected_language == 'HINDI':
                    ai_reply = f'Aapki bus {bus_no} abhi {eta_data["current_location"]} ke paas hai. Yeh {eta_data["eta_minutes"]} minute mein pahuchegi.'
                elif self.selected_language == 'MARATHI':
                    ai_reply = f'Tumchi bus {bus_no} sadhya {eta_data["current_location"]} javal aahe. Ti {eta_data["eta_minutes"]} minutant pohochal.'
                else:
                    ai_reply = f'Your bus {bus_no} is currently near {eta_data["current_location"]}. It will arrive in {eta_data["eta_minutes"]} minutes.'
            else:
                if self.selected_language == 'HINDI':
                    ai_reply = 'Kripya apna guntavya sthan ya prashna spasht roop se batayein. Main MSRTC Enquiry Officer hoon.'
                elif self.selected_language == 'MARATHI':
                    ai_reply = 'Krupya tumcha pravas thikan kinva prashna spasht pane sanga. Me MSRTC Enquiry Officer aahe.'
                else:
                    ai_reply = 'Please clearly state your destination or query. I am the MSRTC Enquiry Officer.'

        self.speak_ai_response(ai_reply, voice)

    def speak_ai_response(self, text, voice='en-IN-NeerjaNeural'):
        self.log_msg('AI', f'MSRTC Helpdesk Officer: "{text}"')

        if HAS_EDGE_TTS:
            def _play():
                try:
                    mp3_path = os.path.abspath('temp_ivr_response.mp3')
                    async def _gen():
                        communicate = edge_tts.Communicate(text, voice)
                        await communicate.save(mp3_path)
                    
                    asyncio.run(_gen())
                    if sys.platform == 'darwin':
                        subprocess.run(['afplay', mp3_path])
                    elif sys.platform.startswith('win'):
                        os.system(f'start /min wmplayer "{mp3_path}"')
                    else:
                        subprocess.run(['mpg123', '-q', mp3_path])
                except Exception as e:
                    print(f'TTS Playback error: {e}')

            threading.Thread(target=_play, daemon=True).start()


if __name__ == '__main__':
    root = tk.Tk()
    app = IVRSimulatorGUI(root)
    root.mainloop()
