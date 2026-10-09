import pyaudio
import math
import struct
import threading
import tkinter as tk
from tkinter import ttk, messagebox
import audioop

class LiveAudioMonitor:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Live Audio Monitor & Tone Generator")
        self.root.geometry("500x480")
        self.root.configure(bg="#1e1e2e")
        
        self.p = pyaudio.PyAudio()
        self.is_running = False
        
        self.input_devices = []
        self.output_devices = []
        self.input_indices = []
        self.output_indices = []
        
        self.load_devices()
        self.build_ui()
        
    def load_devices(self):
        for i in range(self.p.get_device_count()):
            info = self.p.get_device_info_by_index(i)
            name = info.get('name', f'Device {i}')
            if info.get('maxInputChannels', 0) > 0:
                self.input_devices.append(f"[{i}] {name}")
                self.input_indices.append(i)
            if info.get('maxOutputChannels', 0) > 0:
                self.output_devices.append(f"[{i}] {name}")
                self.output_indices.append(i)

    def build_ui(self):
        style = ttk.Style()
        style.theme_use('default')
        style.configure('TCombobox', fieldbackground='#2f3542', background='#2f3542', foreground='white')
        
        lbl_title = tk.Label(self.root, text="Live Hardware Monitor", font=('Helvetica', 16, 'bold'), bg='#1e1e2e', fg='#70a1ff')
        lbl_title.pack(pady=15)
        
        frame = tk.Frame(self.root, bg="#1e1e2e")
        frame.pack(padx=20, fill='x')
        
        tk.Label(frame, text="Select Microphone (Input):", bg='#1e1e2e', fg='#a4b0be', font=('Helvetica', 10, 'bold')).pack(anchor='w')
        self.combo_mic = ttk.Combobox(frame, values=self.input_devices, state='readonly', width=50)
        if self.input_devices: self.combo_mic.current(0)
        self.combo_mic.pack(pady=(0, 15))
        
        tk.Label(frame, text="Select Speaker (Output to SIM800L):", bg='#1e1e2e', fg='#a4b0be', font=('Helvetica', 10, 'bold')).pack(anchor='w')
        self.combo_spk = ttk.Combobox(frame, values=self.output_devices, state='readonly', width=50)
        if self.output_devices: self.combo_spk.current(0)
        self.combo_spk.pack(pady=(0, 20))
        
        tk.Label(frame, text="Select Monitor (Play caller on Mac):", bg='#1e1e2e', fg='#a4b0be', font=('Helvetica', 10, 'bold')).pack(anchor='w')
        self.combo_mon = ttk.Combobox(frame, values=self.output_devices, state='readonly', width=50)
        if self.output_devices: self.combo_mon.current(0)
        self.combo_mon.pack(pady=(0, 5))
        
        self.loopback_var = tk.BooleanVar(value=False)
        self.chk_loopback = tk.Checkbutton(frame, text="Play caller's voice LIVE on Mac Monitor (Input Test)", variable=self.loopback_var, bg='#1e1e2e', fg='white', selectcolor='#2f3542', font=('Helvetica', 10))
        self.chk_loopback.pack(anchor='w', pady=(0, 5))
        
        self.play_out_var = tk.BooleanVar(value=False)
        self.chk_play_out = tk.Checkbutton(frame, text="Play AI.wav out to caller (Output Test)", variable=self.play_out_var, bg='#1e1e2e', fg='white', selectcolor='#2f3542', font=('Helvetica', 10))
        self.chk_play_out.pack(anchor='w', pady=(0, 20))
        
        # Volume Meter
        tk.Label(frame, text="Incoming Audio Volume (From Phone):", bg='#1e1e2e', fg='#2ed573', font=('Helvetica', 10, 'bold')).pack(anchor='w')
        self.meter = ttk.Progressbar(frame, orient='horizontal', length=460, mode='determinate', maximum=32767)
        self.meter.pack(pady=(5, 15))

        self.btn_toggle = tk.Button(self.root, text="START LIVE TEST", font=('Helvetica', 12, 'bold'), bg='#2ed573', fg='white', command=self.toggle_test, height=2)
        self.btn_toggle.pack(fill='x', padx=20, pady=5)
        
    def toggle_test(self):
        if self.is_running:
            self.is_running = False
            self.btn_toggle.config(text="START LIVE TEST", bg='#2ed573')
            self.meter['value'] = 0
        else:
            self.is_running = True
            self.btn_toggle.config(text="STOP TEST", bg='#ff4757')
            threading.Thread(target=self.audio_output_loop, daemon=True).start()
            threading.Thread(target=self.audio_input_loop, daemon=True).start()

    def audio_output_loop(self):
        try:
            if not self.play_out_var.get():
                return
                
            import wave
            import os
            
            idx = self.combo_spk.current()
            dev_idx = self.output_indices[idx]
            
            if os.path.exists("AI.wav"):
                wf = wave.open("AI.wav", 'rb')
                stream = self.p.open(format=self.p.get_format_from_width(wf.getsampwidth()),
                                     channels=wf.getnchannels(),
                                     rate=wf.getframerate(),
                                     output=True,
                                     output_device_index=dev_idx)
                
                while self.is_running:
                    data = wf.readframes(1024)
                    if len(data) == 0:
                        wf.rewind()
                        data = wf.readframes(1024)
                    stream.write(data)
                    
                wf.close()
                stream.stop_stream()
                stream.close()
            else:
                stream = self.p.open(format=pyaudio.paFloat32, channels=1, rate=16000, output=True, output_device_index=dev_idx)
                t = 0.0
                while self.is_running:
                    samples = []
                    for _ in range(1600):
                        samples.append(0.3 * math.sin(2 * math.pi * 440 * t))
                        t += 1.0 / 16000
                    stream.write(struct.pack('f' * len(samples), *samples))
                stream.stop_stream()
                stream.close()
        except Exception as e:
            print("Output Error:", e)

    def audio_input_loop(self):
        try:
            idx = self.combo_mic.current()
            dev_idx = self.input_indices[idx]
            stream = self.p.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True, frames_per_buffer=1024, input_device_index=dev_idx)
            
            mon_stream = None
            if self.loopback_var.get():
                try:
                    mon_idx = self.combo_mon.current()
                    mon_dev_idx = self.output_indices[mon_idx]
                    mon_stream = self.p.open(format=pyaudio.paInt16, channels=1, rate=16000, output=True, output_device_index=mon_dev_idx)
                except Exception as e:
                    print("Could not open monitor stream:", e)

            while self.is_running:
                data = stream.read(1024, exception_on_overflow=False)
                
                # Play live to Mac speakers if loopback is enabled
                if mon_stream:
                    mon_stream.write(data)
                
                # Calculate RMS volume
                rms = audioop.rms(data, 2)
                # Update GUI meter
                self.root.after(0, self.update_meter, rms)
                
            stream.stop_stream()
            stream.close()
            
            if mon_stream:
                mon_stream.stop_stream()
                mon_stream.close()
                
        except Exception as e:
            print("Input Error:", e)
            
    def update_meter(self, rms_value):
        if self.is_running:
            self.meter['value'] = min(rms_value * 2, 32767) # Multiply by 2 for visual boost

    def run(self):
        self.root.mainloop()
        self.is_running = False
        self.p.terminate()

if __name__ == "__main__":
    app = LiveAudioMonitor()
    app.run()
