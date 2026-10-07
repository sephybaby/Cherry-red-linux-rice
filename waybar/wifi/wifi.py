#!/usr/bin/env python

import os
import re
import subprocess
from gi.repository import Gtk, GLib, Gdk
import gi
gi.require_version("Gtk", "4.0")


IFACE = "wlan0"


def run(command):
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True
        )

        return result.stdout

    except Exception:
        return ""


def get_connected():

    output = run(
        f"iwctl station {IFACE} show"
    )

    for line in output.splitlines():

        if "Connected network" in line:

            name = line.split(
                "Connected network",
                1
            )[1].strip()

            return name

    return None


def get_networks():

    output = run(
        f"iwctl station {IFACE} get-networks"
    )

    # Remove ANSI terminal colour/control sequences
    output = re.sub(
        r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])',
        '',
        output
    )

    networks = []

    for line in output.splitlines():

        line = line.rstrip()

        if not line.strip():
            continue

        # Skip table headers
        if (
            "Available networks" in line
            or "Network name" in line
            or line.strip().startswith("---")
        ):
            continue

        # Connected network has a > marker
        connected = line.lstrip().startswith(">")

        if connected:
            line = line.lstrip()[1:].lstrip()

        # iwd separates columns using multiple spaces
        parts = re.split(
            r"\s{2,}",
            line.strip()
        )

        if len(parts) < 3:
            continue

        name = parts[0].strip()
        security = parts[1].strip()
        signal = parts[2].strip()

        if not name:
            continue

        # iwd hides signal strength as ****
        # Connected network gets full strength for now
        percent = 100 if connected else 0

        networks.append(
            (name, percent)
        )

    # Remove duplicates
    result = {}

    for name, percent in networks:

        if name not in result:
            result[name] = percent

    return list(result.items())


class WifiWindow(Gtk.Window):

    def __init__(self, app):

        super().__init__(
            application=app
        )

        self.app = app

        self.set_title(
            "Wi-Fi"
        )

        self.set_default_size(
            420,
            480
        )

        self.set_resizable(
            False
        )

        self.set_decorated(
            False
        )

        self.set_modal(
            True
        )

        self.set_hide_on_close(
            True
        )

        # Main container
        self.box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10
        )

        self.box.set_margin_top(14)
        self.box.set_margin_bottom(14)
        self.box.set_margin_start(14)
        self.box.set_margin_end(14)

        self.set_child(
            self.box
        )

        # Header
        header = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=8
        )

        title = Gtk.Label(
            label="Wi-Fi"
        )

        title.set_xalign(0)

        title.set_hexpand(True)

        title.set_markup(
            "<b>Wi-Fi</b>"
        )

        header.append(title)

        refresh = Gtk.Button(
            label="↻"
        )

        refresh.set_tooltip_text(
            "Refresh networks"
        )

        refresh.connect(
            "clicked",
            lambda _:
                self.refresh()
        )

        header.append(refresh)

        self.box.append(
            header
        )

        # Connected network label
        self.connected_label = Gtk.Label()

        self.connected_label.set_xalign(0)

        self.box.append(
            self.connected_label
        )

        # Scrolled network list
        self.scrolled = Gtk.ScrolledWindow()

        self.scrolled.set_vexpand(
            True
        )

        self.scrolled.set_policy(
            Gtk.PolicyType.NEVER,
            Gtk.PolicyType.AUTOMATIC
        )

        self.list_box = Gtk.ListBox()

        self.list_box.set_selection_mode(
            Gtk.SelectionMode.NONE
        )

        self.scrolled.set_child(
            self.list_box
        )

        self.box.append(
            self.scrolled
        )

        self.password_box = None
        self.password_entry = None

        self.refresh()

    def clear_list(self):

        child = self.list_box.get_first_child()

        while child:

            next_child = child.get_next_sibling()

            self.list_box.remove(
                child
            )

            child = next_child

    def refresh(self):

        self.clear_list()

        connected = get_connected()

        if connected:

            self.connected_label.set_markup(
                f"<b>Connected:</b> {connected}"
            )

        else:

            self.connected_label.set_text(
                "Not connected"
            )

        networks = get_networks()

        for name, percent in networks:

            self.add_network(
                name,
                percent,
                name == connected
            )

        return False

    def add_network(
        self,
        name,
        percent,
        connected
    ):

        row = Gtk.ListBoxRow()

        row.add_css_class(
            "wifi-row"
        )

        if connected:

            row.add_css_class(
                "connected"
            )

        button = Gtk.Button()

        button.set_has_frame(
            False
        )

        button.set_hexpand(
            True
        )

        button.connect(
            "clicked",
            lambda _,
            n=name:
                self.network_clicked(n)
        )

        content = Gtk.Box(
            orientation=Gtk.Orientation.HORIZONTAL,
            spacing=10
        )

        content.set_margin_top(9)
        content.set_margin_bottom(9)
        content.set_margin_start(10)
        content.set_margin_end(10)

        # Wi-Fi icon
        icon = Gtk.Label(
            label=""
        )

        icon.set_width_chars(
            2
        )

        content.append(
            icon
        )

        # Network name
        label = Gtk.Label(
            label=name
        )

        label.set_xalign(0)

        label.set_hexpand(
            True
        )

        label.set_ellipsize(
            3
        )

        content.append(
            label
        )

        # Connected indicator
        if connected:

            status = Gtk.Label(
                label="✓"
            )

            status.add_css_class(
                "connected-check"
            )

            content.append(
                status
            )

        button.set_child(
            content
        )

        row.set_child(
            button
        )

        self.list_box.append(
            row
        )

    def network_clicked(
        self,
        name
    ):

        connected = get_connected()

        if connected == name:

            subprocess.Popen([
                "notify-send",
                "Wi-Fi",
                f"Already connected to {name}"
            ])

            return

        self.show_password_prompt(
            name
        )

    def show_password_prompt(
        self,
        name
    ):

        if self.password_box:

            try:
                self.password_box.unparent()

            except Exception:
                pass

            self.password_box = None

        self.password_box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=10
        )

        self.password_box.add_css_class(
            "password-box"
        )

        title = Gtk.Label(
            label=f"Password for {name}"
        )

        title.add_css_class(
            "password-title"
        )

        title.set_xalign(0)

        self.password_box.append(
            title
        )

        self.password_entry = Gtk.Entry()

        self.password_entry.set_placeholder_text(
            "Enter password..."
        )

        self.password_entry.set_visibility(
            False
        )

        self.password_entry.set_input_purpose(
            Gtk.InputPurpose.PASSWORD
        )

        self.password_entry.add_css_class(
            "password-entry"
        )

        self.password_box.append(
            self.password_entry
        )

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

        buttons.append(
            cancel
        )

        buttons.append(
            connect
        )

        self.password_box.append(
            buttons
        )

        self.box.append(
            self.password_box
        )

        self.password_entry.grab_focus()

    def hide_password_prompt(self):

        if self.password_box:

            try:
                self.password_box.unparent()

            except Exception:
                pass

            self.password_box = None
            self.password_entry = None

    def do_connect(
        self,
        name
    ):

        if not self.password_entry:
            return

        password = (
            self.password_entry
            .get_text()
            .strip()
        )

        if not password:
            return

        self.hide_password_prompt()

        try:

            result = subprocess.run(
                [
                    "iwctl",
                    "--passphrase",
                    password,
                    "station",
                    IFACE,
                    "connect",
                    name
                ],
                capture_output=True,
                text=True
            )

            if result.returncode == 0:

                subprocess.Popen([
                    "notify-send",
                    "Wi-Fi",
                    f"Connected to {name}"
                ])

                GLib.timeout_add(
                    1000,
                    self.refresh
                )

            else:

                error = (
                    result.stderr.strip()
                    or result.stdout.strip()
                    or "Connection failed"
                )

                subprocess.Popen([
                    "notify-send",
                    "Wi-Fi",
                    f"Failed to connect to {name}: {error}"
                ])

                GLib.timeout_add(
                    500,
                    lambda:
                        self.show_password_prompt(
                            name
                        )
                        or False
                )

        except Exception as e:

            subprocess.Popen([
                "notify-send",
                "Wi-Fi",
                f"Wi-Fi error: {e}"
            ])


class WifiApp(Gtk.Application):

    def __init__(self):

        super().__init__(
            application_id="local.waybar.Wifi"
        )

    def do_activate(self):

        window = WifiWindow(
            self
        )

        window.present()


# =========================================
# CSS
# =========================================

css = Gtk.CssProvider()

css.load_from_path(
    os.path.expanduser(
        "~/.config/waybar/wifi/style.css"
    )
)

display = Gdk.Display.get_default()

if display:

    Gtk.StyleContext.add_provider_for_display(
        display,
        css,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )


# =========================================
# Start
# =========================================

app = WifiApp()

app.run()
