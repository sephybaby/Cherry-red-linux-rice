#!/usr/bin/env python3
import re
import subprocess
import threading
import tkinter as tk
from tkinter import simpledialog

BG = "#24070d"
PANEL = "#351019"
PINK = "#ffb3c1"
TEXT = "#f5dce1"
MUTED = "#c58d9a"
ACCENT = "#ff4566"
WIFI_DEVICE = "wlan0"


class WifiWindow:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Wi-Fi")
        width, height = 420, 480
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()
        x = (screen_width - width) // 2
        y = (screen_height - height) // 2
        self.root.geometry(f"{width}x{height}+{x}+{y}")
        self.root.resizable(False, False)
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.configure(bg=BG)
        self.root.bind("<Escape>", self.close)
        self.root.bind("<FocusOut>", self.on_focus_out)

        self.busy = False
        self.networks = []

        box = tk.Frame(self.root, bg=BG)
        box.pack(fill="both", expand=True, padx=20, pady=18)

        header = tk.Frame(box, bg=BG)
        header.pack(fill="x", pady=(0, 12))

        tk.Label(
            header,
            text="Wi-Fi",
            font=("InconsolataGo", 18, "bold"),
            fg=PINK,
            bg=BG,
        ).pack(side="left")

        tk.Button(
            header,
            text="↻",
            command=self.refresh,
            font=("InconsolataGo", 15),
            fg=PINK,
            bg=PANEL,
            activebackground=ACCENT,
            activeforeground="white",
            relief="flat",
            bd=0,
            padx=10,
        ).pack(side="right")

        self.status = tk.Label(
            box,
            text="Scanning networks...",
            font=("InconsolataGo", 10),
            fg=MUTED,
            bg=BG,
            anchor="w",
            wraplength=370,
            justify="left",
        )
        self.status.pack(fill="x", pady=(0, 10))

        self.listbox = tk.Frame(box, bg=BG)
        self.listbox.pack(fill="both", expand=True)

        tk.Label(
            box,
            text="Select a network to connect",
            font=("InconsolataGo", 9),
            fg=MUTED,
            bg=BG,
        ).pack(anchor="w", pady=(10, 0))

        self.root.after(200, self.root.focus_force)
        self.refresh()
        self.root.mainloop()

    def run_iwctl(self, args, timeout=15, passphrase=None):
        command = ["iwctl"]
        if passphrase is not None:
            command.extend(["--passphrase", passphrase])
        command.extend(args)
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

    def refresh(self):
        if self.busy:
            return
        self.busy = True
        self.status.config(text="Scanning networks...", fg=MUTED)
        threading.Thread(target=self.scan_worker, daemon=True).start()

    def scan_worker(self):
        try:
            self.run_iwctl(["station", WIFI_DEVICE, "scan"], timeout=20)
            result = self.run_iwctl(
                ["station", WIFI_DEVICE, "get-networks"], timeout=15
            )
            networks = []
            for line in result.stdout.splitlines():
                # Strip ANSI colour codes emitted by iwctl.
                line = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", line)
                line = line.replace("\x1b", "")
                # iwctl table rows look like:
                # >   Wif       psk       ****
                #     My WiFi   psk       ****
                match = re.match(
                    r"^\s*(>)?\s*(.+?)\s{2,}(psk|open|8021x)\s{2,}",
                    line,
                    re.IGNORECASE,
                )
                if not match:
                    continue
                connected = bool(match.group(1))
                ssid = match.group(2).strip()
                security = match.group(3).lower()
                if ssid and not any(item["ssid"] == ssid for item in networks):
                    networks.append(
                        {"ssid": ssid, "connected": connected, "security": security}
                    )
                elif ssid:
                    for item in networks:
                        if item["ssid"] == ssid:
                            item["connected"] = item["connected"] or connected
                            break

            self.root.after(
                0, lambda items=networks: self.show_networks(items))
        except Exception as exc:
            self.root.after(0, lambda err=str(exc): self.show_error(err))

    def show_error(self, error):
        self.busy = False
        self.status.config(text=f"Could not scan: {error}", fg=ACCENT)

    def show_networks(self, networks):
        self.busy = False
        self.networks = networks
        for child in self.listbox.winfo_children():
            child.destroy()

        if not networks:
            self.status.config(
                text="No networks found. Try refresh.",
                fg=MUTED,
            )
            return

        self.status.config(text=f"{len(networks)} network(s) found", fg=MUTED)

        for item in networks:
            ssid = item["ssid"]
            connected = item["connected"]
            prefix = "✓  " if connected else "󰤨  "
            button = tk.Button(
                self.listbox,
                text=f"{prefix}{ssid}",
                command=lambda network=item: self.connect(network),
                font=("InconsolataGo", 11),
                fg=PINK if connected else TEXT,
                bg=PANEL,
                activebackground=ACCENT,
                activeforeground="white",
                relief="flat",
                bd=0,
                anchor="w",
                padx=12,
                pady=7,
                cursor="hand2",
            )
            button.pack(fill="x", pady=2)

    def connect(self, network):
        if self.busy:
            return

        if network["connected"]:
            self.status.config(text=f"Already connected to {
                               network['ssid']}", fg=PINK)
            return

        passphrase = None
        if network["security"] != "open":
            passphrase = simpledialog.askstring(
                "Wi-Fi password",
                f'Enter the password for "{network["ssid"]}":',
                show="*",
                parent=self.root,
            )
            if passphrase is None:
                return

        self.busy = True
        self.status.config(text=f"Connecting to {network['ssid']}...", fg=PINK)
        threading.Thread(
            target=self.connect_worker,
            args=(network["ssid"], passphrase),
            daemon=True,
        ).start()

    def connect_worker(self, ssid, passphrase):
        try:
            args = ["station", WIFI_DEVICE, "connect", ssid]
            result = self.run_iwctl(
                args,
                timeout=60,
                passphrase=passphrase,
            )
            output = (result.stdout + "\n" + result.stderr).strip()
            failed = any(
                word in output.lower()
                for word in ("failed", "error", "invalid", "not configured")
            )
            success = result.returncode == 0 and not failed
            message = (
                f"Connected to {ssid}!"
                if success
                else f"Could not connect: {output[-160:] or 'iwctl returned an error'}"
            )
            self.root.after(
                0,
                lambda msg=message, ok=success: self.finish_connect(msg, ok),
            )
        except Exception as exc:
            self.root.after(
                0,
                lambda msg=f"Connection error: {
                    exc}": self.finish_connect(msg, False),
            )

    def finish_connect(self, message, success):
        self.busy = False
        self.status.config(text=message, fg=PINK if success else ACCENT)
        if success:
            self.root.after(1200, self.refresh)

    def on_focus_out(self, event):
        self.root.after(200, self.check_focus)

    def check_focus(self):
        try:
            if self.root.winfo_exists() and self.root.focus_displayof() is None:
                self.close()
        except tk.TclError:
            pass

    def close(self, event=None):
        try:
            self.root.destroy()
        except tk.TclError:
            pass


if __name__ == "__main__":
    WifiWindow()
