import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
import serial
import serial.tools.list_ports
import threading
import time

class MatrixCalculatorGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Matrix Calculator Controller")
        self.root.geometry("800x600")

        self.serial_port = None
        self.is_connected = False
        self.read_thread = None
        self.stop_read = False

        # --- Style ---
        style = ttk.Style()
        style.configure("TButton", padding=6, relief="flat", background="#ccc")
        style.configure("TLabel", padding=6)

        # --- Connection Frame ---
        conn_frame = ttk.LabelFrame(root, text="Connection", padding=10)
        conn_frame.pack(fill="x", padx=10, pady=5)

        ttk.Label(conn_frame, text="Port:").pack(side="left")
        self.port_combo = ttk.Combobox(conn_frame, width=10)
        self.port_combo.pack(side="left", padx=5)
        self.refresh_ports()

        ttk.Label(conn_frame, text="Baud:").pack(side="left")
        self.baud_combo = ttk.Combobox(conn_frame, width=10, values=["9600", "115200"])
        self.baud_combo.set("115200")
        self.baud_combo.pack(side="left", padx=5)

        self.btn_connect = ttk.Button(conn_frame, text="Connect", command=self.toggle_connection)
        self.btn_connect.pack(side="left", padx=5)

        self.btn_refresh = ttk.Button(conn_frame, text="Refresh", command=self.refresh_ports)
        self.btn_refresh.pack(side="left", padx=5)

        # --- Tabs ---
        self.notebook = ttk.Notebook(root)
        self.notebook.pack(fill="both", expand=True, padx=10, pady=5)

        self.create_input_tab()
        self.create_generate_tab()
        self.create_compute_tab()
        self.create_setting_tab()

        # --- Status Bar ---
        self.status_var = tk.StringVar()
        self.status_var.set("Disconnected")
        status_bar = ttk.Label(root, textvariable=self.status_var, relief="sunken", anchor="w")
        status_bar.pack(side="bottom", fill="x")

    def refresh_ports(self):
        ports = [port.device for port in serial.tools.list_ports.comports()]
        self.port_combo['values'] = ports
        if ports:
            self.port_combo.current(0)

    def toggle_connection(self):
        if not self.is_connected:
            try:
                port = self.port_combo.get()
                baud = self.baud_combo.get()
                self.serial_port = serial.Serial(port, baud, timeout=0.1)
                self.is_connected = True
                self.btn_connect.config(text="Disconnect")
                self.status_var.set(f"Connected to {port} at {baud}")
                
                self.stop_read = False
                self.read_thread = threading.Thread(target=self.read_serial_loop)
                self.read_thread.daemon = True
                self.read_thread.start()
            except Exception as e:
                messagebox.showerror("Connection Error", str(e))
        else:
            self.stop_read = True
            if self.serial_port:
                self.serial_port.close()
            self.is_connected = False
            self.btn_connect.config(text="Connect")
            self.status_var.set("Disconnected")

    def read_serial_loop(self):
        while not self.stop_read and self.serial_port and self.serial_port.is_open:
            try:
                if self.serial_port.in_waiting > 0:
                    data = self.serial_port.read(self.serial_port.in_waiting)
                    try:
                        text = data.decode('utf-8', errors='ignore')
                    except:
                        text = str(data)
                    
                    # Update UI in main thread
                    self.root.after(0, self.append_to_console, text)
                    
                    # Auto-reply for Settings Mode
                    self.handle_settings_auto_reply(text)
            except Exception as e:
                print(f"Read error: {e}")
                break
            time.sleep(0.01)

    def append_to_console(self, text):
        # Append to the console of the currently active tab (if it has one)
        current_tab = self.notebook.select()
        tab_id = self.notebook.index(current_tab)
        
        # Compute Tab Console (Index 2)
        if tab_id == 2: 
            self.compute_console.insert(tk.END, text)
            self.compute_console.see(tk.END)
        # Generate Tab Console (Index 1)
        elif tab_id == 1:
            self.gen_console.insert(tk.END, text)
            self.gen_console.see(tk.END)
        # Setting Tab Console (Index 3)
        elif tab_id == 3:
            self.setting_console.insert(tk.END, text)
            self.setting_console.see(tk.END)

    def send_data(self, data):
        if self.is_connected and self.serial_port:
            try:
                self.serial_port.write(data.encode('utf-8'))
            except Exception as e:
                messagebox.showerror("Send Error", str(e))
        else:
            messagebox.showwarning("Not Connected", "Please connect to a serial port first.")

    # --- Input Tab ---
    def create_input_tab(self):
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="Input Mode")

        frame = ttk.Frame(tab, padding=20)
        frame.pack(fill="both", expand=True)

        ttk.Label(frame, text="Matrix Dimensions:").grid(row=0, column=0, sticky="w")
        
        dim_frame = ttk.Frame(frame)
        dim_frame.grid(row=1, column=0, sticky="w", pady=5)
        
        ttk.Label(dim_frame, text="Rows (M):").pack(side="left")
        self.input_m = ttk.Entry(dim_frame, width=5)
        self.input_m.pack(side="left", padx=5)
        
        ttk.Label(dim_frame, text="Cols (N):").pack(side="left")
        self.input_n = ttk.Entry(dim_frame, width=5)
        self.input_n.pack(side="left", padx=5)

        ttk.Label(frame, text="Matrix Data (Space separated):").grid(row=2, column=0, sticky="w", pady=(10,0))
        self.input_data = scrolledtext.ScrolledText(frame, height=10)
        self.input_data.grid(row=3, column=0, sticky="nsew", pady=5)

        btn_send = ttk.Button(frame, text="Send Matrix", command=self.send_input_matrix)
        btn_send.grid(row=4, column=0, sticky="e", pady=10)
        
        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(3, weight=1)

    def send_input_matrix(self):
        m = self.input_m.get().strip()
        n = self.input_n.get().strip()
        data = self.input_data.get("1.0", tk.END).replace('\n', ' ').strip()
        
        if not m or not n or not data:
            messagebox.showwarning("Input Error", "Please fill all fields.")
            return

        # Format: M <space> N <space> Data <Enter>
        payload = f"{m} {n} {data}\r"
        self.send_data(payload)

    # --- Generate Tab ---
    def create_generate_tab(self):
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="Generate Mode")

        frame = ttk.Frame(tab, padding=20)
        frame.pack(fill="both", expand=True)

        ttk.Label(frame, text="Generate Random Matrix").pack(anchor="w")
        
        dim_frame = ttk.Frame(frame)
        dim_frame.pack(anchor="w", pady=10)
        
        ttk.Label(dim_frame, text="Rows (M):").pack(side="left")
        self.gen_m = ttk.Entry(dim_frame, width=5)
        self.gen_m.pack(side="left", padx=5)
        
        ttk.Label(dim_frame, text="Cols (N):").pack(side="left")
        self.gen_n = ttk.Entry(dim_frame, width=5)
        self.gen_n.pack(side="left", padx=5)

        btn_gen = ttk.Button(dim_frame, text="Generate", command=self.send_generate_cmd)
        btn_gen.pack(side="left", padx=20)

        ttk.Label(frame, text="Output:").pack(anchor="w", pady=(10,0))
        self.gen_console = scrolledtext.ScrolledText(frame, height=15)
        self.gen_console.pack(fill="both", expand=True, pady=5)

    def send_generate_cmd(self):
        m = self.gen_m.get().strip()
        n = self.gen_n.get().strip()
        
        if not m or not n:
            messagebox.showwarning("Input Error", "Please enter dimensions.")
            return
            
        # Generate mode expects single digits without spaces/enter
        # Assuming M and N are single digits as per Verilog logic
        self.send_data(f"{m}{n}")

    # --- Compute Tab ---
    def create_compute_tab(self):
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="Compute Mode")

        frame = ttk.Frame(tab, padding=20)
        frame.pack(fill="both", expand=True)

        ttk.Label(frame, text="Interactive Console").pack(anchor="w")
        ttk.Label(frame, text="Note: Select Operation using DIP switches on FPGA first.", font=("Arial", 8, "italic")).pack(anchor="w")

        self.compute_console = scrolledtext.ScrolledText(frame, height=15, state='normal')
        self.compute_console.pack(fill="both", expand=True, pady=5)

        input_frame = ttk.Frame(frame)
        input_frame.pack(fill="x", pady=5)

        self.compute_input = ttk.Entry(input_frame)
        self.compute_input.pack(side="left", fill="x", expand=True, padx=(0, 5))
        self.compute_input.bind("<Return>", lambda e: self.send_compute_cmd())

        btn_send = ttk.Button(input_frame, text="Send", command=self.send_compute_cmd)
        btn_send.pack(side="right")
        
        btn_clear = ttk.Button(frame, text="Clear Console", command=lambda: self.compute_console.delete(1.0, tk.END))
        btn_clear.pack(anchor="e")

    def send_compute_cmd(self):
        cmd = self.compute_input.get()
        if cmd:
            self.send_data(cmd) # Send raw input
            self.compute_console.insert(tk.END, f"> {cmd}\n")
            self.compute_input.delete(0, tk.END)

    # --- Setting Tab ---
    def create_setting_tab(self):
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="Settings")

        frame = ttk.Frame(tab, padding=20)
        frame.pack(fill="both", expand=True)

        # Config inputs
        cfg_frame = ttk.LabelFrame(frame, text="Configuration", padding=10)
        cfg_frame.pack(fill="x", pady=10)

        ttk.Label(cfg_frame, text="Max Dimension:").grid(row=0, column=0, sticky="w", pady=5)
        self.set_max_dim = ttk.Entry(cfg_frame, width=10)
        self.set_max_dim.insert(0, "5")
        self.set_max_dim.grid(row=0, column=1, padx=10)

        ttk.Label(cfg_frame, text="Max Value:").grid(row=1, column=0, sticky="w", pady=5)
        self.set_max_val = ttk.Entry(cfg_frame, width=10)
        self.set_max_val.insert(0, "9")
        self.set_max_val.grid(row=1, column=1, padx=10)

        ttk.Label(cfg_frame, text="Matrices Per Size:").grid(row=2, column=0, sticky="w", pady=5)
        self.set_mat_per_size = ttk.Entry(cfg_frame, width=10)
        self.set_mat_per_size.insert(0, "2")
        self.set_mat_per_size.grid(row=2, column=1, padx=10)

        self.auto_reply_var = tk.BooleanVar()
        ttk.Checkbutton(cfg_frame, text="Enable Auto-Reply (Check this before entering Setting Mode on FPGA)", 
                        variable=self.auto_reply_var).grid(row=3, column=0, columnspan=2, pady=10, sticky="w")

        ttk.Label(frame, text="Log:").pack(anchor="w")
        self.setting_console = scrolledtext.ScrolledText(frame, height=10)
        self.setting_console.pack(fill="both", expand=True, pady=5)

    def handle_settings_auto_reply(self, text):
        if not self.auto_reply_var.get():
            return

        # Simple state machine based on received characters
        # FPGA sends 'D', 'V', 'M', 'S'
        if 'D' in text:
            val = self.set_max_dim.get().strip()
            self.root.after(100, lambda: self.send_data(f"{val}\r"))
            self.root.after(0, lambda: self.append_to_console(f"[Auto] Sent Max Dim: {val}\n"))
        elif 'V' in text:
            val = self.set_max_val.get().strip()
            self.root.after(100, lambda: self.send_data(f"{val}\r"))
            self.root.after(0, lambda: self.append_to_console(f"[Auto] Sent Max Val: {val}\n"))
        elif 'M' in text:
            val = self.set_mat_per_size.get().strip()
            self.root.after(100, lambda: self.send_data(f"{val}\r"))
            self.root.after(0, lambda: self.append_to_console(f"[Auto] Sent Mat Per Size: {val}\n"))
        elif 'S' in text:
            self.root.after(0, lambda: self.append_to_console(f"[Auto] Configuration Success!\n"))
            # Optional: Disable auto-reply after success
            # self.auto_reply_var.set(False)

if __name__ == "__main__":
    root = tk.Tk()
    app = MatrixCalculatorGUI(root)
    root.mainloop()
