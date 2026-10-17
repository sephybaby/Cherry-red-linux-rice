#!/usr/bin/env python3
"""Bluetooth popup (bluez / bluetoothctl). Opened by clicking the Bluetooth card."""
import re

import portal_common as pc
from portal_common import Gtk, Pango

DEVICE_LINE = re.compile(r"^Device\s+((?:[0-9A-F]{2}:){5}[0-9A-F]{2})\s+(.*)$", re.I | re.M)
UNNAMED = re.compile(r"^(?:[0-9A-F]{2}[-:]){5}[0-9A-F]{2}$", re.I)
MAX_DEVICES = 30


# --------------------------------------------------------------------------
# bluetoothctl helpers
# --------------------------------------------------------------------------
def bt(*args, timeout=15):
    return pc.run(["bluetoothctl"] + list(args), timeout)


def device_info(mac):
    _, out = bt("info", mac)

    def field(name):
        match = re.search(r"^\s*%s:\s*(.+)$" % name, out, re.M)
        return match.group(1).strip() if match else ""

    rssi = re.search(r"RSSI:.*\((-?\d+)\)", out)
    return {
        "mac": mac,
        "name": field("Alias") or field("Name") or mac,
        "paired": field("Paired") == "yes",
        "connected": field("Connected") == "yes",
        "icon": field("Icon"),
        "rssi": int(rssi.group(1)) if rssi else -999,
    }


def fetch():
    """-> {"error": str} | {"powered": False} | {"powered": True, "devices": [...]}"""
    rc, out = bt("show")
    if rc == 127:
        return {"error": "bluetoothctl is not installed (package: bluez-utils)."}
    if rc != 0 or "no default controller" in out.lower():
        return {"error": "No Bluetooth adapter found. Is bluetooth.service running? "
                         "(systemctl status bluetooth)"}
    if not re.search(r"Powered:\s*yes", out):
        return {"powered": False, "devices": []}

    _, out = bt("devices")
    devices = []
    for mac, _name in DEVICE_LINE.findall(out)[:MAX_DEVICES]:
        info = device_info(mac)
        if not info["paired"] and UNNAMED.match(info["name"]):
            continue  # nameless random devices are just noise
        devices.append(info)
    return {"powered": True, "devices": devices}


def glyph(icon):
    if icon.startswith("audio"):
        return "♫"
    if "keyboard" in icon:
        return "⌨"
    if "mouse" in icon or "gaming" in icon:
        return "◉"
    if "phone" in icon:
        return "☎"
    if "computer" in icon:
        return "▭"
    return "•"


def explain_failure(out, name, verb):
    low = out.lower()
    if "blocked" in low:
        return "Bluetooth is blocked by rfkill. Run: rfkill unblock bluetooth"
    if "not available" in low or "does not exist" in low:
        return "%s isn't available. Turn it on, put it in pairing mode and refresh." % name
    if "authentication" in low:
        return "Pairing with %s was rejected. Put it in pairing mode and try again." % name
    if "timed out" in low:
        return "%s didn't answer in time. Move closer and try again." % name
    detail = out.splitlines()[-1].strip() if out.strip() else ""
    return "Could not %s %s%s." % (verb, name, " (%s)" % detail if detail else "")


# --------------------------------------------------------------------------
# Window
# --------------------------------------------------------------------------
class BluetoothPortal(pc.Portal):
    def __init__(self):
        super().__init__("bluetooth", "Bluetooth")
        self.devices = []
        self._updating = False
        self.hint.set_text("Click a device to connect or disconnect")

        self.switch = Gtk.Switch()
        self.switch.set_valign(Gtk.Align.CENTER)
        self.switch.connect("notify::active", self._on_switch)
        self.header.pack_end(self.switch, False, False, 0)

        self.listbox.connect("row-activated", self._on_row)
        self.refresh(scan=True)

    # -- refresh -----------------------------------------------------------------
    def on_refresh(self):
        self.refresh(scan=True)

    def refresh(self, scan=True):
        if self.busy:
            return
        self.busy = True
        self.set_status("Looking for devices…", busy=True)
        self.bg(self._refresh_worker, scan, False)

    def _refresh_worker(self, scan, keep_status):
        data = fetch()
        scanning = bool(scan and data.get("powered"))
        self.ui(self._show, data, not scanning, keep_status)
        if not scanning:
            return
        bt("--timeout", "8", "scan", "on", timeout=20)
        self.ui(self._show, fetch(), True, keep_status)

    def _show(self, data, final, keep_status):
        if "error" in data:
            self.busy = False
            self._set_switch(False)
            self.clear_list()
            self.set_status(data["error"], "error")
            return

        powered = data["powered"]
        self._set_switch(powered)
        self.devices = data["devices"]
        self._rebuild()

        if not powered:
            self.busy = False
            self.set_status("Bluetooth is off. Flip the switch to turn it on.")
            return
        if not final:
            if not keep_status:
                self.set_status("Scanning for devices…", busy=True)
            return

        self.busy = False
        if keep_status:
            return
        connected = [d["name"] for d in self.devices if d["connected"]]
        if connected:
            self.set_status("Connected to %s" % ", ".join(connected), "ok")
        elif self.devices:
            self.set_status("%d devices · none connected" % len(self.devices))
        else:
            self.set_status("No devices found. Put your device in pairing mode and refresh.")

    def _set_switch(self, state):
        self._updating = True
        self.switch.set_active(state)
        self._updating = False

    # -- power ---------------------------------------------------------------------
    def _on_switch(self, switch, _param):
        if self._updating:
            return
        if self.busy:
            self._set_switch(not switch.get_active())
            return
        want = switch.get_active()
        self.busy = True
        self.set_status("Turning Bluetooth %s…" % ("on" if want else "off"), busy=True)
        self.bg(self._power_worker, want)

    def _power_worker(self, want):
        rc, out = bt("power", "on" if want else "off", timeout=10)
        if "succeeded" not in out.lower():
            self.ui(self._after_action, explain_failure(out, "Bluetooth", "turn on" if want else "turn off"), False)
            return
        self.ui(self._finish_power, want)

    def _finish_power(self, want):
        self.busy = False
        self.refresh(scan=want)

    # -- rows ------------------------------------------------------------------------
    def _rebuild(self):
        self.clear_list()
        ordered = sorted(
            self.devices,
            key=lambda d: (not d["connected"], not d["paired"], -d["rssi"], d["name"].lower()),
        )
        for dev in ordered:
            self.listbox.add(self._row(dev))
        self.listbox.show_all()

    def _row(self, dev):
        row = Gtk.ListBoxRow()
        row.dev = dev
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.add(box)
        if dev["connected"]:
            row.get_style_context().add_class("connected")

        icon = Gtk.Label(label=glyph(dev["icon"]))
        icon.get_style_context().add_class("signal")
        box.pack_start(icon, False, False, 0)

        name = Gtk.Label(label=dev["name"])
        name.set_xalign(0)
        name.set_ellipsize(Pango.EllipsizeMode.END)
        name.get_style_context().add_class("name")
        box.pack_start(name, True, True, 0)

        if dev["paired"] and not dev["connected"]:
            box.pack_start(
                self.action_button("forget", lambda d=dev: self._forget(d)), False, False, 0)

        state = "connected" if dev["connected"] else "paired" if dev["paired"] else "new"
        meta = Gtk.Label(label=state)
        meta.get_style_context().add_class("meta")
        box.pack_start(meta, False, False, 0)
        return row

    def _on_row(self, _listbox, row):
        dev = getattr(row, "dev", None)
        if dev is None or self.busy:
            return
        self.busy = True
        if dev["connected"]:
            self.set_status("Disconnecting from %s…" % dev["name"], busy=True)
            self.bg(self._disconnect_worker, dev)
        else:
            verb = "Connecting to" if dev["paired"] else "Pairing with"
            self.set_status("%s %s…" % (verb, dev["name"]), busy=True)
            self.bg(self._connect_worker, dev)

    # -- actions ---------------------------------------------------------------------------
    def _connect_worker(self, dev):
        mac, name = dev["mac"], dev["name"]
        if not dev["paired"]:
            _, out = bt("pair", mac, timeout=45)
            low = out.lower()
            if "pairing successful" not in low and "already exists" not in low \
                    and "alreadyexists" not in low:
                self.ui(self._after_action, explain_failure(out, name, "pair with"), False)
                return
            bt("trust", mac)
            self.ui(self.set_status, "Connecting to %s…" % name, "info", True)
        _, out = bt("connect", mac, timeout=30)
        if device_info(mac)["connected"]:
            self.ui(self._after_action, "Connected to %s" % name, True)
        else:
            self.ui(self._after_action, explain_failure(out, name, "connect to"), False)

    def _disconnect_worker(self, dev):
        bt("disconnect", dev["mac"], timeout=15)
        if device_info(dev["mac"])["connected"]:
            self.ui(self._after_action, "Could not disconnect from %s." % dev["name"], False)
        else:
            self.ui(self._after_action, "Disconnected from %s" % dev["name"], True)

    def _forget(self, dev):
        if self.busy:
            return
        self.busy = True
        self.set_status("Forgetting %s…" % dev["name"], busy=True)
        self.bg(self._forget_worker, dev)

    def _forget_worker(self, dev):
        _, out = bt("remove", dev["mac"])
        ok = "removed" in out.lower()
        self.ui(self._after_action,
                "Forgot %s" % dev["name"] if ok else "Could not forget %s." % dev["name"], ok)

    def _after_action(self, message, ok):
        self.busy = False
        self.set_status(message, "ok" if ok else "error")
        self.busy = True
        self.bg(self._refresh_worker, False, True)  # redraw list, keep the message


if __name__ == "__main__":
    pc.main("bluetooth", BluetoothPortal)
