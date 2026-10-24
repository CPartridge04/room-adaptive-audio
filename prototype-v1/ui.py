import math
import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from compensation import distance, position_to_gains
from audio_engine import AudioEngine


class Application:
    def __init__(self, root):
        self.root = root
        self.engine = AudioEngine()
        self.room = (4., 4.)
        self.speakers = ((1., .5), (3., .5))
        self.listener = (2., 2.)
        self.reference = (2., 2.)
        self.refs = tuple(distance(self.reference, s) for s in self.speakers)
        root.title('Two-speaker room audio prototype')
        root.geometry('1000x780')
        panel = ttk.Frame(root, padding=12)
        panel.pack(fill='both', expand=True)
        self.device = ttk.Combobox(panel, state='readonly', width=65)
        self.device.grid(row=0, column=0, columnspan=3, sticky='ew')
        self.device.bind('<<ComboboxSelected>>', lambda e: self.engine.stop())
        ttk.Button(panel, text='Refresh outputs', command=lambda: self.guard(self.refresh)).grid(row=0, column=3)
        buttons = ttk.Frame(panel)
        buttons.grid(row=1, column=0, columnspan=4, sticky='w', pady=8)
        for label, action in [('Load WAV', self.load), ('Play / resume', lambda: self.engine.play(self.device_id())),
                              ('Pause', self.engine.pause), ('Stop', self.engine.stop),
                              ('Test left', lambda: self.engine.identify(self.device_id(), 0)),
                              ('Test right', lambda: self.engine.identify(self.device_id(), 1))]:
            ttk.Button(buttons, text=label, command=lambda a=action: self.guard(a)).pack(side='left', padx=2)
        self.filename = ttk.Label(panel, text='No file loaded • channel tests use a fixed quiet level and reset playback')
        self.filename.grid(row=2, column=0, columnspan=4, sticky='w')
        self.source = tk.StringVar(value='Original stereo')
        self.mode = tk.StringVar(value='Position compensation')
        for col, variable, values in [(0, self.source, ['Original stereo', 'Mono test']),
                                      (2, self.mode, ['Position compensation', 'Manual'])]:
            combo = ttk.Combobox(panel, state='readonly', textvariable=variable, values=values)
            combo.grid(row=3, column=col, columnspan=2, sticky='ew', pady=8)
            combo.bind('<<ComboboxSelected>>', lambda e: self.update())
        self.left = tk.DoubleVar(value=.25)
        self.right = tk.DoubleVar(value=.25)
        self.master = tk.DoubleVar(value=.1)
        self.scales = []
        for row, label, variable in [(4, 'Manual left', self.left), (5, 'Manual right', self.right), (6, 'Master volume', self.master)]:
            ttk.Label(panel, text=label).grid(row=row, column=0, sticky='w')
            scale = ttk.Scale(panel, from_=0, to=1, variable=variable, command=lambda v: self.update())
            scale.grid(row=row, column=1, columnspan=3, sticky='ew')
            self.scales.append(scale)
        self.fields = []
        geometry = ttk.Frame(panel)
        geometry.grid(row=7, column=0, columnspan=4, sticky='w', pady=8)
        for label, value in [('Width', 4), ('Depth', 4), ('L x', 1), ('L y', .5), ('R x', 3), ('R y', .5)]:
            ttk.Label(geometry, text=label).pack(side='left')
            field = ttk.Entry(geometry, width=5)
            field.insert(0, str(value))
            field.pack(side='left', padx=3)
            self.fields.append(field)
        ttk.Button(geometry, text='Apply metres', command=lambda: self.guard(self.apply_geometry)).pack(side='left')
        ttk.Button(panel, text='Set current position as reference', command=self.set_reference).grid(row=8, column=0, columnspan=4, sticky='w')
        self.readout = ttk.Label(panel)
        self.readout.grid(row=9, column=0, columnspan=4, sticky='w', pady=6)
        self.warning = ttk.Label(panel, foreground='#b34000')
        self.warning.grid(row=10, column=0, columnspan=4, sticky='w')
        self.canvas = tk.Canvas(panel, background='#eef3f7', height=340, highlightthickness=0)
        self.canvas.grid(row=11, column=0, columnspan=4, sticky='nsew')
        self.canvas.bind('<Configure>', lambda e: self.draw())
        self.canvas.bind('<Button-1>', self.move)
        self.canvas.bind('<B1-Motion>', self.move)
        self.status = ttk.Label(panel)
        self.status.grid(row=12, column=0, columnspan=4, sticky='w')
        panel.rowconfigure(11, weight=1)
        for col in range(4):
            panel.columnconfigure(col, weight=1)
        
        self.guard(self.refresh)
        self.update()
        self.poll()

    def guard(self, action):
        try:
            action()
        except Exception as exc:
            messagebox.showerror('Audio prototype', str(exc), parent=self.root)

    def refresh(self):
        self.engine.stop()
        self.devices = self.engine.devices()
        self.device['values'] = [f'{i}: {name}' for i, name in self.devices]
        if self.devices:
            self.device.current(0)
        else:
            self.device.set('')
            raise ValueError('No stereo output found. Connect your speakers and refresh.')

    def device_id(self):
        index = self.device.current()
        if index < 0:
            raise ValueError('Select a stereo output device.')
        return self.devices[index][0]

    def load(self):
        path = filedialog.askopenfilename(filetypes=[('WAV audio', '*.wav'), ('All files', '*')])
        if path:
            self.engine.load(path)
            self.filename.config(text=f'{path} • {self.engine.rate} Hz • {len(self.engßine.data)/self.engine.rate:.1f} s') # type: ignore

    def apply_geometry(self):
        w, h, lx, ly, rx, ry = [float(e.get()) for e in self.fields]
        if not all(math.isfinite(v) for v in (w, h, lx, ly, rx, ry)) or w <= 0 or h <= 0:
            raise ValueError('Use finite coordinates and positive room dimensions.')
        if not (0 <= lx <= w and 0 <= rx <= w and 0 <= ly <= h and 0 <= ry <= h):
            raise ValueError('Speakers must be inside the room.')
        self.room, self.speakers = (w, h), ((lx, ly), (rx, ry))
        self.listener = (min(w, self.listener[0]), min(h, self.listener[1]))
        # Preserve stored reference distances until explicitly reset by the user.
        self.update()

    def set_reference(self):
        self.reference = self.listener
        self.refs = tuple(distance(self.reference, s) for s in self.speakers)
        self.update()

    def transform(self):
        w, h = self.room
        return min(max(1, self.canvas.winfo_width()-70)/w,
                   max(1, self.canvas.winfo_height()-60)/h), 35, 30

    def move(self, event):
        scale, ox, oy = self.transform()
        self.listener = (max(0, min(self.room[0], (event.x-ox)/scale)),
                         max(0, min(self.room[1], (event.y-oy)/scale)))
        self.update()

    def draw(self):
        c = self.canvas
        c.delete('all')
        scale, ox, oy = self.transform()
        w, h = self.room
        c.create_rectangle(ox, oy, ox+w*scale, oy+h*scale, outline='#73869a', width=2)
        c.create_text(ox, 13, text=f'(0, 0) • x →, y ↓ • room {w:g} × {h:g} m', anchor='w')
        for point, label, color in [(self.speakers[0], 'L', '#176cb0'), (self.speakers[1], 'R', '#176cb0'),
                                     (self.listener, 'Listener', '#bd4c26')]:
            x, y = ox+point[0]*scale, oy+point[1]*scale
            c.create_oval(x-8, y-8, x+8, y+8, fill=color, outline='white')
            c.create_text(x, y+19, text=label)

    def update(self):
        result = position_to_gains(self.listener, self.speakers, self.refs)
        manual = self.mode.get() == 'Manual'
        gains = (self.left.get(), self.right.get()) if manual else result.gains
        for scale in self.scales[:2]:
            scale.state(['!disabled'] if manual else ['disabled'])
        self.engine.set_controls(*gains, self.master.get(), self.source.get() == 'Mono test') # type: ignore
        self.readout.config(text=f'Listener ({self.listener[0]:.2f}, {self.listener[1]:.2f}) m | distances L {result.distances[0]:.3f}, R {result.distances[1]:.3f} m\n'
                           f'Gains L {gains[0]:.3f}, R {gains[1]:.3f} | master {self.master.get():.3f} | stored reference distances {self.refs[0]:.3f}, {self.refs[1]:.3f} m')
        self.warning.config(text=(f'Compensation limited: requested L {result.requested[0]:.3f}, R {result.requested[1]:.3f}; target cannot be maintained.'
                                  if result.limited and not manual else ''))
        self.draw()

    def poll(self):
        state, cursor, clipped, diagnostic = self.engine.status()
        seconds = cursor / self.engine.rate if self.engine.rate else 0
        self.status.config(text=f'{state} • {seconds:.2f} s' + (' • CLIPPING: output limited to ±1' if clipped else '') + (f' • {diagnostic}' if diagnostic else ''))
        self.root.after(100, self.poll)

    def close(self):
        self.engine.close()
        self.root.destroy()
