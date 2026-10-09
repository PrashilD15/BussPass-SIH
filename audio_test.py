import pyaudio
import wave
import time
import math
import struct
import threading
import tkinter as tk
from tkinter import ttk, messagebox
import os

class AudioTesterGUI:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Hardware Audio Diagnostic")
        self.root.geometry("500x450")
        self.root.configure(bg="#1e1e2e")
        
        self.p = pyaudio.PyAudio()
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
        
        lbl_title = tk.Label(self.root, text="USB Sound Card Tester", font=('Helvetica', 16, 'bold'), bg='#1e1e2e', fg='#70a1ff')
        lbl_title.pack(pady=15)
        
        frame = tk.Frame(self.root, bg="#1e1e2e")
        frame.pack(padx=20, fill='x')
        
        tk.Label(frame, text="Select Microphone (Input):", bg='#1e1e2e', fg='#a4b0be', font=('Helvetica', 10, 'bold')).pack(anchor='w')
        self.combo_mic = ttk.Combobox(frame, values=self.input_devices, state='readonly', width=50)
        if self.input_devices: self.combo_mic.current(0)
        self.combo_mic.pack(pady=(0, 15))
        
        tk.Label(frame, text="Select Speaker (Output):", bg='#1e1e2e', fg='#a4b0be', font=('Helvetica', 10, 'bold')).pack(anchor='w')
        self.combo_spk = ttk.Combobox(frame, values=self.output_devices, state='readonly', width=50)
        if self.output_devices: self.combo_spk.current(0)
        self.combo_spk.pack(pady=(0, 20))
        
        self.btn_out = tk.Button(self.root, text="1. Play Beep (Test Output)", font=('Helvetica', 11, 'bold'), bg='#2ed573', fg='white', command=self.test_output, height=2)
        self.btn_out.pack(fill='x', padx=20, pady=5)
        
        self.btn_in = tk.Button(self.root, text="2. Record Mic for 5s (Test Input)", font=('Helvetica', 11, 'bold'), bg='#ff4757', fg='white', command=self.start_record_thread, height=2)
        self.btn_in.pack(fill='x', padx=20, pady=5)
        
        self.btn_play = tk.Button(self.root, text="3. Playback Recording on Mac", font=('Helvetica', 11, 'bold'), bg='#ffa502', fg='white', command=self.play_recording, height=2, state='disabled')
        self.btn_play.pack(fill='x', padx=20, pady=5)
        
        self.lbl_status = tk.Label(self.root, text="Ready.", font=('Helvetica', 10), bg='#1e1e2e', fg='#a4b0be')
        self.lbl_status.pack(pady=15)

    def test_output(self):
        try:
            idx = self.combo_spk.current()
            dev_idx = self.output_indices[idx]
            
            self.lbl_status.config(text="Playing Beep... Listen on your phone earpiece!", fg='#2ed573')
            self.root.update()
            
            out_stream = self.p.open(format=pyaudio.paFloat32, channels=1, rate=16000, output=True, output_device_index=dev_idx)
            samples = []
            for i in range(16000 * 2):
                samples.append(0.5 * math.sin(2 * math.pi * 440 * (i / 16000.0)))
            out_stream.write(struct.pack('f' * len(samples), *samples))
            out_stream.stop_stream()
            out_stream.close()
            
            self.lbl_status.config(text="Beep finished playing.", fg='#a4b0be')
        except Exception as e:
            messagebox.showerror("Output Error", str(e))

    def start_record_thread(self):
        self.btn_in.config(state='disabled')
        self.btn_out.config(state='disabled')
        self.lbl_status.config(text="RECORDING... SPEAK INTO YOUR PHONE NOW! (5s)", fg='#ff4757')
        threading.Thread(target=self.test_input, daemon=True).start()
        
    def test_input(self):
        try:
            idx = self.combo_mic.current()
            dev_idx = self.input_indices[idx]
            
            in_stream = self.p.open(format=pyaudio.paInt16, channels=1, rate=16000, input=True, frames_per_buffer=1024, input_device_index=dev_idx)
            frames = []
            for _ in range(0, int(16000 / 1024 * 5)):
                data = in_stream.read(1024, exception_on_overflow=False)
                frames.append(data)
            in_stream.stop_stream()
            in_stream.close()
            
            wf = wave.open("test_recording.wav", 'wb')
            wf.setnchannels(1)
            wf.setsampwidth(self.p.get_sample_size(pyaudio.paInt16))
            wf.setframerate(16000)
            wf.writeframes(b''.join(frames))
            wf.close()
            
            self.root.after(0, self.on_record_finish)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("Input Error", str(e)))
            self.root.after(0, self.reset_buttons)
            
    def on_record_finish(self):
        self.lbl_status.config(text="Recording saved successfully! Click 'Playback' to hear it.", fg='#2ed573')
        self.btn_play.config(state='normal')
        self.reset_buttons()
        
    def reset_buttons(self):
        self.btn_in.config(state='normal')
        self.btn_out.config(state='normal')
        
    def play_recording(self):
        if os.path.exists("test_recording.wav"):
            # Play on default mac speaker using afplay
            threading.Thread(target=lambda: os.system("afplay test_recording.wav"), daemon=True).start()
            self.lbl_status.config(text="Playing back recording on your Mac speakers...", fg='#ffa502')
        else:
            messagebox.showwarning("File Missing", "No recording found.")

    def run(self):
        self.root.mainloop()
        self.p.terminate()

if __name__ == "__main__":
    app = AudioTesterGUI()
    app.run()
