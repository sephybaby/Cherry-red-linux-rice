#!/usr/bin/env python3
"""Shared window, styling and helpers for the Wi-Fi and Bluetooth popups."""
import atexit
import os
import re
import signal
import subprocess
import sys
import threading
import traceback

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk, Pango  # noqa: E402,F401

HERE = os.path.dirname(os.path.realpath(__file__))
CSS_PATH = os.path.join(HERE, "style.css")

# wifi-close.sh reads these to close the popups when you switch workspace.
PIDFILES = {
    "wifi": "/tmp/waybar-wifi.pid",
    "bluetooth": "/tmp/waybar-bluetooth.pid",
}

_ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def clean(text):
    """Strip ANSI colour codes that iwctl / bluetoothctl like to emit."""
    return _ANSI.sub("", text or "").replace("\x1b", "").replace("\r", "")


def run(cmd, timeout=15):
    """Run a command and return (returncode, cleaned stdout+stderr).

    returncode is 124 when the command timed out and 127 when it is missing,
    so callers can show a useful message instead of failing silently.
    """
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
        )
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except FileNotFoundError:
        return 127, "%s: command not found" % cmd[0]
    return proc.returncode, clean(proc.stdout + "\n" + proc.stderr).strip()


def _unlink(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def _running_pid(path, kind):
    """PID stored in `path` if it is still our popup, else None."""
    try:
        with open(path) as handle:
            pid = int(handle.read().strip())
        os.kill(pid, 0)
        with open("/proc/%d/cmdline" % pid, "rb") as handle:
            cmdline = handle.read()
    except (OSError, ValueError):
        return None
    if pid == os.getpid() or ("%s.py" % kind).encode() not in cmdline:
        return None
    return pid


def claim_instance(kind):
    """Click the card again and the popup closes (toggle).
    Opening one popup also closes the other."""
    mine = PIDFILES[kind]
    pid = _running_pid(mine, kind)
    if pid:
        os.kill(pid, signal.SIGTERM)
        _unlink(mine)
        sys.exit(0)

    for other, path in PIDFILES.items():
        if other == kind:
            continue
        other_pid = _running_pid(path, other)
        if other_pid:
            os.kill(other_pid, signal.SIGTERM)
        _unlink(path)

    with open(mine, "w") as handle:
        handle.write(str(os.getpid()))

    def cleanup():
        try:
            with open(mine) as handle:
                if int(handle.read().strip()) == os.getpid():
                    _unlink(mine)
        except (OSError, ValueError):
            pass

    atexit.register(cleanup)


# --------------------------------------------------------------------------
# Base window
# --------------------------------------------------------------------------
class Portal(Gtk.Window):
    """Frameless, centred popup: header, status banner, scrolling list,
    an `extra` area for subclasses and a hint line."""

    def __init__(self, kind, title, size=(440, 560)):
        # Becomes the Wayland app-id / X11 class -> use it in Hyprland rules.
        GLib.set_prgname("%s-portal" % kind)
        GLib.set_application_name(title)
        super().__init__(title=title)

        self.busy = False      # a connect / forget / pair action is running
        self.scanning = 0      # scans in flight (a scan never blocks clicks)
        self.pinned = False    # keep the last action message on screen
        self._gen = 0          # bumped on every refresh; older results are dropped
        self._armed = False

        self._load_css()
        self.set_size_request(*size)
        self.set_resizable(False)
        self.set_decorated(False)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

        # Transparent window so the card's rounded corners show.
        visual = self.get_screen().get_rgba_visual()
        if visual is not None:
            self.set_visual(visual)
        self.set_app_paintable(True)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.get_style_context().add_class("portal-card")
        self.add(card)

        # Header -----------------------------------------------------------
        self.header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.title_label = Gtk.Label(label=title)
        self.title_label.set_xalign(0)
        self.title_label.get_style_context().add_class("portal-title")
        self.header.pack_start(self.title_label, False, False, 0)
        self.header.pack_end(self._icon_button("✕", self.close_portal), False, False, 0)
        self.refresh_btn = self._icon_button("↻", lambda: self.on_refresh())
        self.header.pack_end(self.refresh_btn, False, False, 0)
        card.pack_start(self.header, False, False, 0)

        # Status banner ----------------------------------------------------
        self.status_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.status_box.get_style_context().add_class("status-box")
        self.spinner = Gtk.Spinner()
        self.spinner.set_no_show_all(True)
        self.status_label = Gtk.Label(label="")
        self.status_label.set_xalign(0)
        self.status_label.set_hexpand(True)
        self.status_label.set_line_wrap(True)
        self.status_label.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.status_label.set_max_width_chars(46)
        self.status_label.get_style_context().add_class("status-label")
        self.status_box.pack_start(self.spinner, False, False, 0)
        self.status_box.pack_start(self.status_label, True, True, 0)
        card.pack_start(self.status_box, False, False, 0)

        # List -------------------------------------------------------------
        self.listbox = Gtk.ListBox()
        self.listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.add(self.listbox)
        card.pack_start(scroller, True, True, 0)

        # Subclass area (password prompt etc.) and hint ---------------------
        self.extra = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        card.pack_start(self.extra, False, False, 0)
        self.hint = Gtk.Label(label="")
        self.hint.set_xalign(0)
        self.hint.get_style_context().add_class("hint")
        card.pack_start(self.hint, False, False, 0)

        # Behaviour --------------------------------------------------------
        self.connect("key-press-event", self._on_key)
        self.connect("focus-in-event", self._on_focus_in)
        self.connect("focus-out-event", self._on_focus_out)
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGTERM, self._on_signal)
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, signal.SIGINT, self._on_signal)

    # -- styling -------------------------------------------------------------
    @staticmethod
    def _load_css():
        provider = Gtk.CssProvider()
        try:
            provider.load_from_path(CSS_PATH)
        except GLib.Error as exc:
            print("Could not load %s: %s" % (CSS_PATH, exc.message), file=sys.stderr)
            return
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
        )

    @staticmethod
    def _icon_button(text, callback):
        button = Gtk.Button(label=text)
        button.set_focus_on_click(False)
        button.get_style_context().add_class("icon-btn")
        button.connect("clicked", lambda *_: callback())
        return button

    # -- status ----------------------------------------------------------------
    def set_status(self, text, kind="info", busy=False):
        """kind: "info" | "ok" | "error". Errors get a red banner."""
        context = self.status_box.get_style_context()
        context.remove_class("ok")
        context.remove_class("error")
        if kind in ("ok", "error"):
            context.add_class(kind)
        self.status_label.set_text(text)
        if busy:
            self.spinner.show()
            self.spinner.start()
        else:
            self.spinner.stop()
            self.spinner.hide()

    # -- list --------------------------------------------------------------------
    def clear_list(self):
        for child in self.listbox.get_children():
            self.listbox.remove(child)

    @staticmethod
    def action_button(label, callback):
        button = Gtk.Button(label=label)
        button.set_relief(Gtk.ReliefStyle.NONE)
        button.set_focus_on_click(False)
        button.set_valign(Gtk.Align.CENTER)
        button.get_style_context().add_class("row-action")
        button.connect("clicked", lambda *_: callback())
        return button

    # -- threading -----------------------------------------------------------------
    def bg(self, func, *args):
        """Run func in a thread. If it crashes, unlock the UI and show why
        instead of leaving the popup silently stuck."""
        def runner():
            try:
                func(*args)
            except Exception as exc:  # noqa: BLE001
                traceback.print_exc()
                self.ui(self._worker_failed, exc)
        threading.Thread(target=runner, daemon=True).start()

    def _worker_failed(self, exc):
        self.busy = False
        self.scanning = 0
        self.pinned = True
        self.set_status("Unexpected error: %s" % exc, "error")

    def can_update_status(self):
        return not (self.busy or self.pinned)

    @staticmethod
    def ui(func, *args):
        """Run func(*args) on the GTK thread."""
        def call():
            func(*args)
            return False
        GLib.idle_add(call)

    # -- closing ---------------------------------------------------------------------
    def close_portal(self, *_):
        Gtk.main_quit()

    def on_escape(self):
        """Return True if Escape was handled (e.g. closing a sub-prompt)."""
        return False

    def on_refresh(self):
        pass

    def _on_key(self, _widget, event):
        if event.keyval == Gdk.KEY_Escape:
            if not self.on_escape():
                self.close_portal()
            return True
        return False

    def _on_focus_in(self, *_):
        self._armed = True  # only auto-close once we have really had focus
        return False

    def _on_focus_out(self, *_):
        if self._armed:
            GLib.timeout_add(300, self._focus_check)
        return False

    def _focus_check(self):
        if not self.is_active():
            self.close_portal()
        return False

    def _on_signal(self):
        Gtk.main_quit()
        return GLib.SOURCE_REMOVE


def main(kind, cls):
    claim_instance(kind)
    window = cls()
    window.show_all()
    Gtk.main()
