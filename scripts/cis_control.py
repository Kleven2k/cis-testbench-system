"""
CIS Testbench Control GUI
UART register interface for sensor_ctrl parameters.

Protocol:
  Write: AA <addr> <data> 55
  Read:  BB <addr> 55
  Response: CC <addr> <data> 55

Register map:
  0x00  CTRL: [7]=remote_mode [2]=cds_enable [1]=soft_reset [0]=start
  0x01  exposure_us[7:0]
  0x02  exposure_us[15:8]
  0x03  dwell_us[7:0]
  0x04  dwell_us[15:8]
  0x05  mode: [0]=read_mode [1]=skip_alternate (photosense) [3:2]=disp_gain [4]=invert_pol
  0x06  reset_us  (0-255)
  0x07  cds_delay_us (0-255)

Pixel readback (read-only):
  0x08 + i*2      pixel[i] hi nibble: {4'b0, pixel[i][11:8]}
  0x09 + i*2      pixel[i] lo byte:   pixel[i][7:0]
  i = 0..63  ->  addresses 0x08..0x87
"""

import tkinter as tk
from tkinter import ttk, messagebox, filedialog
import serial
import serial.tools.list_ports
import threading
import time
import os
import datetime

# ──────────────────────────────────────────────
# Register addresses
# ──────────────────────────────────────────────
REG_CTRL       = 0x00
REG_EXP_LO     = 0x01
REG_EXP_HI     = 0x02
REG_DWELL_LO   = 0x03
REG_DWELL_HI   = 0x04
REG_MODE       = 0x05
REG_RESET_US   = 0x06
REG_CDS_US     = 0x07

CTRL_START     = 0x01
CTRL_SOFT_RST  = 0x02
CTRL_CDS_EN    = 0x04
CTRL_REMOTE    = 0x80

CELL  = 56          # pixels per sensor pixel on canvas
GRID  = 8           # 8x8 sensor array
FRAMES_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "frames")


class CISControl:
    def __init__(self, root):
        self.root = root
        self.root.title("CIS Sensor Control")
        self.root.resizable(False, False)

        self.port          = None
        self.remote_active = False
        self._live_active  = False
        self._live_thread  = None
        self._port_lock    = threading.RLock()

        os.makedirs(FRAMES_DIR, exist_ok=True)
        self._build_ui()

    # ──────────────────────────────────────────
    # UI construction
    # ──────────────────────────────────────────
    def _build_ui(self):
        pad = dict(padx=8, pady=4)

        # ── Left panel: controls ──────────────
        left = ttk.Frame(self.root)
        left.grid(row=0, column=0, sticky="nsew", padx=4, pady=4)

        # Port selection
        port_frame = ttk.LabelFrame(left, text="Serial Port")
        port_frame.grid(row=0, column=0, sticky="ew", **pad)

        self.port_var = tk.StringVar()
        self.port_combo = ttk.Combobox(port_frame, textvariable=self.port_var, width=12, state="readonly")
        self.port_combo.grid(row=0, column=0, padx=4, pady=4)
        ttk.Button(port_frame, text="Refresh", command=self._refresh_ports).grid(row=0, column=1, padx=4)
        ttk.Button(port_frame, text="Connect", command=self._connect).grid(row=0, column=2, padx=4)
        self.status_label = ttk.Label(port_frame, text="Disconnected", foreground="red")
        self.status_label.grid(row=0, column=3, padx=8)
        self._refresh_ports()

        # Timing parameters
        timing_frame = ttk.LabelFrame(left, text="Timing Parameters")
        timing_frame.grid(row=1, column=0, sticky="ew", **pad)

        self.exposure_var  = tk.IntVar(value=100)
        self.dwell_var     = tk.IntVar(value=100)
        self.reset_us_var  = tk.IntVar(value=10)
        self.cds_delay_var = tk.IntVar(value=2)

        params = [
            ("Exposure time (µs)", self.exposure_var,  1, 1000, 1),
            ("Pixel dwell (µs)",   self.dwell_var,     1, 1000, 1),
            ("Reset hold (µs)",    self.reset_us_var,  1,  255, 1),
            ("CDS delay (µs)",     self.cds_delay_var, 1,  255, 1),
        ]
        for i, (label, var, lo, hi, step) in enumerate(params):
            ttk.Label(timing_frame, text=label, width=20, anchor="w").grid(row=i, column=0, padx=4, pady=2)
            ttk.Scale(timing_frame, from_=lo, to=hi, variable=var, orient="horizontal", length=220).grid(row=i, column=1, padx=4)
            ttk.Label(timing_frame, textvariable=var, width=5).grid(row=i, column=2, padx=2)
            ttk.Spinbox(timing_frame, from_=lo, to=hi, textvariable=var, width=6, increment=step).grid(row=i, column=3, padx=4)

        # Mode flags
        flags_frame = ttk.LabelFrame(left, text="Mode")
        flags_frame.grid(row=2, column=0, sticky="ew", **pad)

        self.cds_en_var     = tk.BooleanVar(value=False)
        self.read_mode_var  = tk.BooleanVar(value=False)
        self.photosense_var = tk.BooleanVar(value=True)
        self.invert_pol_var = tk.BooleanVar(value=False)
        self.disp_gain_var  = tk.IntVar(value=0)

        ttk.Checkbutton(flags_frame, text="CDS enable",        variable=self.cds_en_var).grid(row=0, column=0, padx=8, pady=3)
        ttk.Checkbutton(flags_frame, text="Single-pixel mode", variable=self.read_mode_var).grid(row=0, column=1, padx=8)
        ttk.Checkbutton(flags_frame, text="Skip alternate px", variable=self.photosense_var).grid(row=0, column=2, padx=8)
        ttk.Checkbutton(flags_frame, text="Invert polarity (higher ADC = brighter)",
                        variable=self.invert_pol_var).grid(row=0, column=3, padx=8)

        ttk.Label(flags_frame, text="HDMI gain:").grid(row=1, column=0, padx=8, pady=3, sticky="e")
        ttk.Combobox(flags_frame, textvariable=self.disp_gain_var,
                     values=[0, 1, 2, 3], width=4, state="readonly").grid(row=1, column=1, padx=4, sticky="w")
        ttk.Label(flags_frame, text="0=auto  1=2×  2=4×  3=8× (boost beyond auto-range)",
                  foreground="gray").grid(row=1, column=2, columnspan=2, padx=4, sticky="w")

        # Actions
        action_frame = ttk.LabelFrame(left, text="Control")
        action_frame.grid(row=3, column=0, sticky="ew", **pad)

        self.remote_btn = ttk.Button(action_frame, text="Enable Remote", command=self._toggle_remote)
        self.remote_btn.grid(row=0, column=0, padx=6, pady=5)
        ttk.Button(action_frame, text="Apply Settings", command=self._apply_settings).grid(row=0, column=1, padx=6)
        ttk.Button(action_frame, text="Start Scan",     command=self._start_scan).grid(row=0, column=2, padx=6)
        ttk.Button(action_frame, text="Soft Reset",     command=self._soft_reset).grid(row=0, column=3, padx=6)

        ttk.Button(action_frame, text="Read Frame",     command=self._read_frame).grid(row=1, column=0, padx=6, pady=5)
        self.live_btn = ttk.Button(action_frame, text="Live View: OFF", command=self._toggle_live)
        self.live_btn.grid(row=1, column=1, padx=6)
        ttk.Button(action_frame, text="Save Frame",     command=self._save_frame).grid(row=1, column=2, padx=6)
        ttk.Button(action_frame, text="Test Read",      command=self._test_read).grid(row=1, column=3, padx=6)
        ttk.Button(action_frame, text="Load Frame",     command=self._load_frame).grid(row=2, column=0, padx=6, pady=5)
        self.dark_btn = ttk.Button(action_frame, text="Set Dark Frame", command=self._set_dark_frame)
        self.dark_btn.grid(row=2, column=1, padx=6)
        ttk.Button(action_frame, text="Clear Dark Frame", command=self._clear_dark_frame).grid(row=2, column=2, padx=6)

        # Log
        log_frame = ttk.LabelFrame(left, text="Log")
        log_frame.grid(row=4, column=0, sticky="ew", **pad)
        self.log = tk.Text(log_frame, height=7, width=58, state="disabled", font=("Courier", 9))
        self.log.grid(row=0, column=0, padx=4, pady=4)
        sb = ttk.Scrollbar(log_frame, command=self.log.yview)
        sb.grid(row=0, column=1, sticky="ns")
        self.log.configure(yscrollcommand=sb.set)

        # ── Right panel: canvas ───────────────
        right = ttk.Frame(self.root)
        right.grid(row=0, column=1, sticky="nsew", padx=4, pady=4)

        ttk.Label(right, text="8×8 Pixel Map (auto-normalized)", font=("TkDefaultFont", 10, "bold")).pack(pady=(8, 2))

        canvas_size = CELL * GRID
        self.canvas = tk.Canvas(right, width=canvas_size, height=canvas_size,
                                bg="#111", highlightthickness=1, highlightbackground="#555")
        self.canvas.pack(padx=8)

        # Create 64 rectangles
        self._rects = []
        for row in range(GRID):
            for col in range(GRID):
                x0, y0 = col * CELL, row * CELL
                r = self.canvas.create_rectangle(x0, y0, x0 + CELL, y0 + CELL,
                                                 fill="#222", outline="#333")
                self._rects.append(r)

        self._stats_var = tk.StringVar(value="min: —   max: —   range: —")
        ttk.Label(right, textvariable=self._stats_var, font=("Courier", 9)).pack(pady=4)

        self._last_pixels = None   # most recent frame for Save Frame
        self._dark_frame  = None   # per-pixel dark baseline for correction (Python canvas)

    # ──────────────────────────────────────────
    # Serial helpers
    # ──────────────────────────────────────────
    def _refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        self.port_combo["values"] = ports
        if ports:
            self.port_combo.set(ports[0])

    def _connect(self):
        if self.port and self.port.is_open:
            self._live_active = False
            self.port.close()
            self.port = None
            self.status_label.config(text="Disconnected", foreground="red")
            self.remote_active = False
            self.remote_btn.config(text="Enable Remote")
            self.live_btn.config(text="Live View: OFF")
            self._log("Disconnected.")
            return
        selected = self.port_var.get()
        if not selected:
            messagebox.showerror("Error", "No port selected.")
            return
        try:
            self.port = serial.Serial(selected, 115200, timeout=0.5)
            self.status_label.config(text=f"Connected: {selected}", foreground="green")
            self._log(f"Connected to {selected} @ 115200 baud.")
        except Exception as e:
            messagebox.showerror("Connection failed", str(e))

    def _write_reg(self, addr, data):
        if not self.port or not self.port.is_open:
            self._log("Not connected.")
            return
        with self._port_lock:
            self.port.write(bytes([0xAA, addr, data, 0x55]))
        self._log(f"  WR  addr=0x{addr:02X}  data=0x{data:02X}")

    def _read_reg(self, addr):
        """Read one register, log result. Returns value or None."""
        if not self.port or not self.port.is_open:
            return None
        with self._port_lock:
            self.port.reset_input_buffer()
            self.port.write(bytes([0xBB, addr, 0x55]))
            resp = self.port.read(4)
        if len(resp) == 4 and resp[0] == 0xCC and resp[1] == addr and resp[3] == 0x55:
            self._log(f"  RD  addr=0x{addr:02X}  data=0x{resp[2]:02X}")
            return resp[2]
        self._log(f"  RD  addr=0x{addr:02X}  bad response: {resp.hex()}")
        return None

    def _read_reg_silent(self, addr):
        """Read one register without logging. Returns value or None."""
        if not self.port or not self.port.is_open:
            return None
        with self._port_lock:
            self.port.reset_input_buffer()
            self.port.write(bytes([0xBB, addr, 0x55]))
            resp = self.port.read(4)
        if len(resp) == 4 and resp[0] == 0xCC and resp[1] == addr and resp[3] == 0x55:
            return resp[2]
        return None

    def _read_frame_data(self, silent=False):
        """Read 64 pixels. Returns list of 12-bit values or None on error."""
        rd = self._read_reg_silent if silent else self._read_reg
        pixels = []
        for i in range(64):
            hi = rd(0x08 + i * 2)
            lo = rd(0x09 + i * 2)
            if hi is None or lo is None:
                return None
            pixels.append(((hi & 0x0F) << 8) | lo)
        return pixels

    # ──────────────────────────────────────────
    # Canvas update
    # ──────────────────────────────────────────
    def _update_canvas(self, pixels):
        """Render pixels on the 8×8 canvas (runs on main thread).

        If a dark frame is set: display = |pixel - dark|, normalised to 0-255.
        Both pixel types (which move in opposite directions with light) will then
        start at 0 (black) in darkness and go bright when light hits them.

        Without a dark frame: raw auto-normalisation, which leaves 'inverted'
        pixels looking white in darkness.

        In photosense mode (isfet_skip), ISFET pixels (row+col even) are blanked.
        """
        photosense  = self.photosense_var.get()
        invert_pol  = self.invert_pol_var.get()

        # Compute per-pixel display values
        if self._dark_frame is not None:
            vals = [abs(pixels[i] - self._dark_frame[i]) for i in range(64)]
        else:
            vals = list(pixels)

        # Determine active pixels (exclude ISFET in photosense mode)
        active = []
        for i in range(64):
            row, col = divmod(i, 8)
            isfet = ((row + col) % 2 == 0)
            if not (photosense and isfet):
                active.append(i)

        active_vals = [vals[i] for i in active]
        lo = min(active_vals)
        hi = max(active_vals)
        span = hi - lo or 1

        for i in range(64):
            row, col = divmod(i, 8)
            isfet = ((row + col) % 2 == 0)
            if photosense and isfet:
                color = "#000000"
            else:
                norm = (vals[i] - lo) / span
                gray = int((norm if invert_pol else (1.0 - norm)) * 255)
                color = f"#{gray:02x}{gray:02x}{gray:02x}"
            self.canvas.itemconfig(self._rects[i], fill=color)

        dark_tag = "  [dark corrected]" if self._dark_frame else ""
        photo_tag = "  [photosense]" if photosense else ""
        self._stats_var.set(
            f"min: {lo} ({lo/4096*1000:.0f} mV)   "
            f"max: {hi} ({hi/4096*1000:.0f} mV)   "
            f"range: {hi - lo} ({(hi-lo)/4096*1000:.0f} mV)"
            + dark_tag + photo_tag
        )

    # ──────────────────────────────────────────
    # Actions
    # ──────────────────────────────────────────
    def _toggle_remote(self):
        if not self.port or not self.port.is_open:
            messagebox.showwarning("Not connected", "Connect to the FPGA first.")
            return
        if not self.remote_active:
            self._write_reg(REG_CTRL, CTRL_REMOTE)
            self.remote_active = True
            self.remote_btn.config(text="Disable Remote")
            self._log("Remote mode ENABLED.")
        else:
            self._live_active = False
            self._write_reg(REG_CTRL, 0x00)
            self.remote_active = False
            self.remote_btn.config(text="Enable Remote")
            self.live_btn.config(text="Live View: OFF")
            self._log("Remote mode DISABLED.")

    def _apply_settings(self):
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode first.")
            return
        exp   = self.exposure_var.get()
        dwell = self.dwell_var.get()
        rst   = self.reset_us_var.get()
        cds   = self.cds_delay_var.get()
        self._log(f"Applying: exp={exp}µs  dwell={dwell}µs  reset={rst}µs  cds={cds}µs")
        self._write_reg(REG_EXP_LO,   exp   & 0xFF)
        self._write_reg(REG_EXP_HI,   (exp  >> 8) & 0xFF)
        self._write_reg(REG_DWELL_LO, dwell & 0xFF)
        self._write_reg(REG_DWELL_HI, (dwell >> 8) & 0xFF)
        self._write_reg(REG_RESET_US, rst  & 0xFF)
        self._write_reg(REG_CDS_US,   cds  & 0xFF)
        ctrl = CTRL_REMOTE | (CTRL_CDS_EN if self.cds_en_var.get() else 0)
        mode = 0x00
        if self.read_mode_var.get():
            mode |= 0x01
        if self.photosense_var.get():
            mode |= 0x02
        mode |= (self.disp_gain_var.get() & 0x03) << 2
        if self.invert_pol_var.get():
            mode |= 0x10
        self._write_reg(REG_CTRL, ctrl)
        self._write_reg(REG_MODE, mode)
        self._log(f"  Photosense: {'ON' if self.photosense_var.get() else 'OFF'}  "
                  f"Gain: {self.disp_gain_var.get()}")

    def _start_scan(self):
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode first.")
            return
        self._apply_settings()
        ctrl = CTRL_REMOTE | CTRL_START | (CTRL_CDS_EN if self.cds_en_var.get() else 0)
        self._log("Sending START pulse...")
        self._write_reg(REG_CTRL, ctrl)
        time.sleep(0.05)
        self._write_reg(REG_CTRL, ctrl & ~CTRL_START)

    def _soft_reset(self):
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode first.")
            return
        self._log("Soft reset...")
        self._write_reg(REG_CTRL, CTRL_REMOTE | CTRL_SOFT_RST)
        time.sleep(0.05)
        self._write_reg(REG_CTRL, CTRL_REMOTE)

    def _read_frame(self):
        """Single-shot frame read — logs all registers and updates canvas."""
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode first.")
            return
        self._log("Reading frame (64 pixels)...")
        pixels = self._read_frame_data(silent=False)
        if pixels is None:
            self._log("  ERROR reading frame.")
            return
        self._last_pixels = pixels
        self._update_canvas(pixels)
        self._log("Frame (12-bit ADC values):")
        for row in range(8):
            line = "  " + "  ".join(f"{pixels[row*8+col]:4d}" for col in range(8))
            self._log(line)

    def _set_dark_frame(self):
        """Use the most recently read frame as the per-pixel dark baseline."""
        if not self._last_pixels:
            messagebox.showwarning("No frame", "Read a frame in darkness first, then click Set Dark Frame.")
            return
        self._dark_frame = list(self._last_pixels)
        self._log("Dark frame set — canvas will now show |pixel - dark| (both pixel types start black).")
        self.dark_btn.config(text="Set Dark Frame ✓")

    def _clear_dark_frame(self):
        self._dark_frame = None
        self.dark_btn.config(text="Set Dark Frame")
        self._log("Dark frame cleared.")

    def _load_frame(self):
        """Open a saved frame .txt file and display it on the canvas."""
        fname = filedialog.askopenfilename(
            title="Load frame file",
            initialdir=FRAMES_DIR,
            filetypes=[("Frame files", "*.txt"), ("All files", "*.*")]
        )
        if not fname:
            return
        try:
            pixels = []
            with open(fname) as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    pixels.extend(int(v) for v in line.split())
            if len(pixels) != 64:
                messagebox.showerror("Load error", f"Expected 64 values, got {len(pixels)}.")
                return
            self._last_pixels = pixels
            self._update_canvas(pixels)
            self._log(f"Loaded: {os.path.basename(fname)}")
        except Exception as e:
            messagebox.showerror("Load error", str(e))

    def _save_frame(self):
        """Save the most recent frame to data/frames/."""
        if not self._last_pixels:
            self._log("No frame to save — read a frame first.")
            return
        ts    = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        fname = os.path.join(FRAMES_DIR, f"frame_{ts}.txt")
        with open(fname, "w") as f:
            f.write("# CIS frame capture — 8x8 pixels, 12-bit ADC values\n")
            f.write(f"# Timestamp: {ts}\n")
            f.write(f"# Exposure: {self.exposure_var.get()} us\n")
            f.write(f"# Dwell: {self.dwell_var.get()} us\n")
            for row in range(8):
                f.write(" ".join(str(self._last_pixels[row*8+col]) for col in range(8)) + "\n")
        self._log(f"  Saved to data/frames/frame_{ts}.txt")

    # ──────────────────────────────────────────
    # Live view
    # ──────────────────────────────────────────
    def _toggle_live(self):
        if not self.remote_active:
            messagebox.showwarning("Remote not active", "Enable remote mode and start a scan first.")
            return
        if self._live_active:
            self._live_active = False
            self.live_btn.config(text="Live View: OFF")
            self._log("Live view stopped.")
        else:
            self._live_active = True
            self.live_btn.config(text="Live View: ON")
            self._log("Live view started — reading frames continuously.")
            self._live_thread = threading.Thread(target=self._live_loop, daemon=True)
            self._live_thread.start()

    def _live_loop(self):
        """Background thread: reads frames and schedules canvas updates on main thread."""
        consecutive_errors = 0
        while self._live_active:
            with self._port_lock:
                pixels = self._read_frame_data(silent=True)
            if pixels is not None:
                consecutive_errors = 0
                self._last_pixels = pixels
                self.root.after(0, self._update_canvas, pixels)
            else:
                consecutive_errors += 1
                if consecutive_errors >= 3:
                    self.root.after(0, self._log, "Live view: too many read errors, stopping.")
                    self._live_active = False
                    self.root.after(0, lambda: self.live_btn.config(text="Live View: OFF"))
                    break
            time.sleep(0.05)   # ~20 fps cap; actual rate limited by 128 UART reads

    # ──────────────────────────────────────────
    # Diagnostics
    # ──────────────────────────────────────────
    def _test_read(self):
        if not self.port or not self.port.is_open:
            messagebox.showwarning("Not connected", "Connect to the FPGA first.")
            return
        self._log("--- UART read diagnostic ---")
        for addr in [REG_CTRL, REG_EXP_LO, REG_EXP_HI]:
            self.port.reset_input_buffer()
            self.port.write(bytes([0xBB, addr, 0x55]))
            time.sleep(0.1)
            avail = self.port.in_waiting
            raw = self.port.read(avail) if avail else b''
            self._log(f"  addr=0x{addr:02X}  avail={avail}  raw={raw.hex()}")

    # ──────────────────────────────────────────
    # Logging
    # ──────────────────────────────────────────
    def _log(self, msg):
        self.log.config(state="normal")
        self.log.insert("end", msg + "\n")
        self.log.see("end")
        self.log.config(state="disabled")


def main():
    root = tk.Tk()
    app = CISControl(root)
    root.mainloop()


if __name__ == "__main__":
    main()
