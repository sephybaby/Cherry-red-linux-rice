#!/usr/bin/env python

import os
import re
import subprocess
from gi.repository import Gtk, GLib, Gdk
import gi
gi.require_version("Gtk", "4.0")


IFACE = "wlan0"


# =========================================================
# Helpers
# =========================================================

def run(cmd):
    try:
        return subprocess.check_output(
            cmd,
            shell=True,
            text=True,
            stderr=subprocess.DEVNULL
        ).strip()
    except subprocess.CalledProcessError:
        return ""


def get_connected():
    output = run(f"iwctl station {IFACE} show")

    match = re.search(
        r"Connected network\s+(.+)",
        output
    )

    return match.group(1).strip() if match else ""


def get_networks():
    output = run(f"iw dev {IFACE} scan")

    networks = []
    current_signal = None

    for line in output.splitlines():

        signal = re.search(
            r"signal:\s*(-?\d+(?:\.\d+)?)",
            line
        )

        if signal:
            current_signal = float(signal.group(1))

        ssid = re.search(
            r"SSID:\s*(.*)",
            line
        )

        if ssid and current_signal is not None:

            name = ssid.group(1).strip()

            if not name:
                continue

            percent = int(
                (current_signal + 90) * 100 / 60
            )

            percent = max(
                0,
                min(100, percent)
            )

            networks.append(
                (name, percent)
            )

    # Remove duplicate SSIDs.
    result = {}

    for name, percent in networks:

        if (
            name not in result
            or percent > result[name]
        ):
            result[name] = percent

    return sorted(
        result.items(),
        key=lambda x: x[1],
        reverse=True
    )


# =========================================================
# Wi-Fi Window
# =========================================================

class WifiWindow(Gtk.Window):

    def __init__(self, app):

        super().__init__(
            application=app,
            title="Wi-Fi"
        )

        self.set_default_size(
            620,
            520
        )

        self.build_ui()

        self.refresh()

    # =====================================================
    # UI
    # =====================================================

    def build_ui(self):

        self.box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10
        )

        self.box.set_margin_top(18)
        self.box.set_margin_bottom(18)
        self.box.set_margin_start(18)
        self.box.set_margin_end(18)

        self.set_child(self.box)

        # -------------------------------------------------
        # Header
        # -------------------------------------------------

        header = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=10
        )

        title = Gtk.Label(
            label="Wi-Fi"
        )

        title.set_markup(
            "<span size='large' weight='bold'>Wi-Fi</span>"
        )

        title.set_xalign(0)

        header.append(title)

        refresh = Gtk.Button(
            label="↻ Refresh"
        )

        refresh.connect(
            "clicked",
            lambda _: self.refresh()
        )

        header.append(refresh)

        self.box.append(header)

        # -------------------------------------------------
        # Current connection
        # -------------------------------------------------

        self.current = Gtk.Label()

        self.current.set_xalign(0)

        self.box.append(
            self.current
        )

        # -------------------------------------------------
        # Separator
        # -------------------------------------------------

        self.box.append(
            Gtk.Separator(
                orientation=Gtk.Orientation.HORIZONTAL
            )
        )

        # -------------------------------------------------
        # Network list
        # -------------------------------------------------

        self.listbox = Gtk.ListBox()

        self.listbox.set_selection_mode(
            Gtk.SelectionMode.NONE
        )

        self.box.append(
            self.listbox
        )

    # =====================================================
    # List handling
    # =====================================================

    def clear_list(self):

        child = self.listbox.get_first_child()

        while child:

            next_child = child.get_next_sibling()

            self.listbox.remove(child)

            child = next_child

    # =====================================================
    # Refresh
    # =====================================================

    def refresh(self):

        self.current.set_text(
            "Scanning for networks..."
        )

        self.clear_list()

        connected = get_connected()

        if connected:

            self.current.set_markup(
                f"<b>Connected:</b> "
                f"{GLib.markup_escape_text(connected)}"
            )

        else:

            self.current.set_text(
                "Not connected"
            )

        # Let GTK update the UI before
        # the scan starts.

        GLib.timeout_add(
            100,
            self.finish_scan,
            connected
        )

    def finish_scan(self, connected):

        networks = get_networks()

        self.clear_list()

        for name, percent in networks:

            row = self.create_row(
                name,
                percent,
                connected
            )

            self.listbox.append(row)

        return False

    # =====================================================
    # Network row
    # =====================================================

    def create_row(
        self,
        name,
        percent,
        connected
    ):

        row = Gtk.ListBoxRow()

        container = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=12
        )

        container.set_margin_top(10)
        container.set_margin_bottom(10)
        container.set_margin_start(12)
        container.set_margin_end(12)

        # -------------------------------------------------
        # Wi-Fi icon
        # -------------------------------------------------

        icon = Gtk.Label(
            label="󰖩"
        )

        container.append(icon)

        # -------------------------------------------------
        # Network name
        # -------------------------------------------------

        label = Gtk.Label()

        label.set_xalign(0)

        safe_name = GLib.markup_escape_text(
            name
        )

        if name == connected:

            label.set_markup(
                f"<b>{safe_name}</b>  "
                f"<span foreground='#7ddc8b'>"
                f"✓ Connected"
                f"</span>"
            )

        else:

            label.set_markup(
                f"<b>{safe_name}</b>"
            )

        container.append(label)

        # -------------------------------------------------
        # Signal
        # -------------------------------------------------

        signal = Gtk.Label(
            label=f"{percent}%"
        )

        signal.set_hexpand(True)

        signal.set_halign(
            Gtk.Align.END
        )

        container.append(signal)

        row.set_child(
            container
        )

        # -------------------------------------------------
        # Click handler
        # -------------------------------------------------

        gesture = Gtk.GestureClick()

        gesture.connect(
            "released",
            lambda *_,
            n=name,
            c=connected:
                self.connect_network(
                    n,
                    c
                )
        )

        row.add_controller(
            gesture
        )

        return row

    # =====================================================
    # Connect
    # =====================================================

    def connect_network(
        self,
        name,
        connected
    ):

        if name == connected:

            subprocess.Popen([
                "notify-send",
                "Wi-Fi",
                f"Already connected to {name}"
            ])

            return

        self.show_password_prompt(
            name
        )

    # =====================================================
    # Password prompt
    # =====================================================

    def show_password_prompt(
        self,
        name
    ):

        if hasattr(
            self,
            "password_box"
        ):

            self.password_box.unparent()

        self.password_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10
        )

        self.password_box.add_css_class(
            "password-box"
        )

        # -------------------------------------------------
        # Title
        # -------------------------------------------------

        title = Gtk.Label(
            label=f"Password for {name}"
        )

        title.add_css_class(
            "password-title"
        )

        title.set_xalign(0)

        # -------------------------------------------------
        # Password entry
        # -------------------------------------------------

        self.password_entry = Gtk.PasswordEntry()

        self.password_entry.set_placeholder_text(
            "Enter password..."
        )

        self.password_entry.set_show_peek_icon(
            True
        )

        self.password_entry.add_css_class(
            "password-entry"
        )

        # -------------------------------------------------
        # Buttons
        # -------------------------------------------------

        buttons = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=8
        )

        buttons.set_halign(
            Gtk.Align.END
        )

        cancel = Gtk.Button(
            label="Cancel"
        )

        cancel.add_css_class(
            "password-cancel"
        )

        cancel.connect(
            "clicked",
            lambda _:
                self.hide_password_prompt()
        )

        connect = Gtk.Button(
            label="Connect"
        )

        connect.add_css_class(
            "password-connect"
        )

        connect.connect(
            "clicked",
            lambda _:
                self.do_connect(name)
        )

        buttons.append(cancel)
        buttons.append(connect)

        # -------------------------------------------------
        # Assemble password box
        # -------------------------------------------------

        self.password_box.append(
            title
        )

        self.password_box.append(
            self.password_entry
        )

        self.password_box.append(
            buttons
        )

        self.box.append(
            self.password_box
        )

        self.password_entry.grab_focus()

    # =====================================================
    # Hide password prompt
    # =====================================================

    def hide_password_prompt(self):

        if hasattr(
            self,
            "password_box"
        ):

            self.password_box.unparent()

            del self.password_box

    # =====================================================
    # Actually connect
    # =====================================================

    def do_connect(
        self,
        name
    ):

        password = self.password_entry.get_text()

        if not password:

            return

        self.hide_password_prompt()

        result = subprocess.run([
            "iwctl",
            "--passphrase",
            password,
            "station",
            IFACE,
            "connect",
            name
        ])

        if result.returncode == 0:

            subprocess.Popen([
                "notify-send",
                "Wi-Fi",
                f"Connected to {name}"
            ])

            GLib.timeout_add(
                500,
                self.refresh
            )

        else:

            subprocess.Popen([
                "notify-send",
                "Wi-Fi",
                f"Failed to connect to {name}"
            ])


# =========================================================
# Application
# =========================================================

class WifiApp(Gtk.Application):

    def __init__(self):

        super().__init__(
            application_id="local.sephy.Wifi"
        )

    def do_activate(self):

        window = WifiWindow(
            self
        )

        window.present()


# =========================================================
# CSS
# =========================================================

css = Gtk.CssProvider()

css.load_from_path(
    os.path.expanduser(
        "~/.config/waybar/wifi/style.css"
    )
)


Gtk.StyleContext.add_provider_for_display(
    Gdk.Display.get_default(),
    css,
    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
)


# =========================================================
# Run
# =========================================================

app = WifiApp()

app.run()
