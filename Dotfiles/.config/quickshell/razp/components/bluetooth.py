#!/usr/bin/env python3
"""Bluetooth popup. Reads BlueZ over D-Bus (instant); bluetoothctl only pairs new devices."""
import re
import time

import portal_common as pc
from portal_common import GLib, Gtk, Pango

BLUEZ = "org.bluez"
ADAPTER_IF = "org.bluez.Adapter1"
DEVICE_IF = "org.bluez.Device1"

UNNAMED = re.compile(r"^(?:[0-9A-F]{2}[-:]){5}[0-9A-F]{2}$", re.I)


# --------------------------------------------------------------------------
# BlueZ helpers
# --------------------------------------------------------------------------
def adapter_path(objs):
    return next((p for p, ifaces in objs.items() if ADAPTER_IF in ifaces), None)


def blocked_by_rfkill():
    _, out = pc.run(["rfkill", "list", "bluetooth"], 5)
    return re.search(r"(Soft|Hard) blocked:\s*yes", out) is not None


def fetch():
    """-> {"error": str} | {"powered": False, ...} | {"powered": True, "devices": [...]}"""
    try:
        objs = pc.managed_objects(BLUEZ)
    except GLib.Error as exc:
        return {"error": "Can't reach BlueZ (%s). Is bluetooth.service running?"
                         % pc.error_text(exc)}
    adapter = adapter_path(objs)
    if adapter is None:
        if blocked_by_rfkill():
            return {"powered": False, "devices": [], "blocked": True, "adapter": None}
        return {"error": "No Bluetooth adapter found. Is bluetooth.service running? "
                         "(systemctl status bluetooth)"}
    if not objs[adapter][ADAPTER_IF].get("Powered"):
        return {"powered": False, "devices": [], "adapter": adapter}

    devices = []
    for path, ifaces in objs.items():
        props = ifaces.get(DEVICE_IF)
        if not props or not path.startswith(adapter + "/"):
            continue
        name = props.get("Alias") or props.get("Name") or props.get("Address", "")
        paired = bool(props.get("Paired"))
        rssi = props.get("RSSI")
        # skip nameless noise and stale unpaired devices that are no longer in range
        if not paired and (UNNAMED.match(name) or rssi is None):
            continue
        devices.append({
            "path": path,
            "mac": props.get("Address", ""),
            "name": name,
            "paired": paired,
            "connected": bool(props.get("Connected")),
            "icon": props.get("Icon", ""),
            "rssi": rssi if rssi is not None else -999,
        })
    return {"powered": True, "devices": devices, "adapter": adapter}


def bt(*args, timeout=15):
    return pc.run(["bluetoothctl"] + list(args), timeout)


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
    if "not available" in low or "does not exist" in low or "notavailable" in low:
        return "%s isn't available. Turn it on, put it in pairing mode and refresh." % name
    if "authentication" in low:
        return "Pairing with %s was rejected. Put it in pairing mode and try again." % name
    if "timed out" in low or "timeout" in low:
        return "%s didn't answer in time. Move closer and try again." % name
    if "inprogress" in low or "in progress" in low:
        return "Bluetooth is busy. Wait a moment and try again."
    detail = out.splitlines()[-1].strip() if out.strip() else ""
    return "Could not %s %s%s." % (verb, name, " (%s)" % detail if detail else "")


# --------------------------------------------------------------------------
# Window
# --------------------------------------------------------------------------
class BluetoothPortal(pc.Portal):
    def __init__(self):
        super().__init__("bluetooth", "Bluetooth")
        self.devices = []
        self.adapter = None
        self._power_busy = False
        self.hint.set_text("Press connect, or click a device")
        self.add_power_switch(self._on_power)
        self.listbox.connect("row-activated", self._on_row)
        self.refresh()

    # -- refresh -----------------------------------------------------------------
    def on_refresh(self):
        self.pinned = False
        self.refresh()

    def refresh(self, scan=True, force=False):
        """Never blocks clicks or the power switch while it scans."""
        if scan and self.scanning and not force:
            return
        self._gen += 1
        if scan:
            self.scanning += 1
            if self.can_update_status():
                self.set_status("Looking for devices…", busy=True)
        self.bg(self._refresh_worker, self._gen, scan)

    def _refresh_worker(self, gen, scan):
        data = fetch()
        do_scan = bool(scan and data.get("powered"))
        state = "partial" if do_scan else ("final" if scan else "none")
        self.ui(self._show, gen, data, state)
        if not do_scan:
            return
        adapter = data["adapter"]
        try:
            pc.dbus_call(BLUEZ, adapter, ADAPTER_IF, "StartDiscovery")
        except GLib.Error:
            pass  # already discovering is fine
        for _ in range(8):  # devices stream in as they are found
            time.sleep(1)
            if gen != self._gen:
                break
            self.ui(self._show, gen, fetch(), "partial")
        try:
            pc.dbus_call(BLUEZ, adapter, ADAPTER_IF, "StopDiscovery")
        except GLib.Error:
            pass
        self.ui(self._show, gen, fetch(), "final")

    def _show(self, gen, data, scan_state):
        if scan_state == "final":
            self.scanning = max(0, self.scanning - 1)
        if gen != self._gen:
            return  # newer refresh (e.g. power toggled) already redrew things

        if "error" in data:
            self.set_switch(False, enabled=False)
            self.devices = []
            self._sync([])
            self.set_status(data["error"], "error")
            return

        powered = data["powered"]
        self.adapter = data.get("adapter") or self.adapter
        self.set_switch(powered)
        self.devices = data["devices"]
        self._sync(self.devices)
        if not self.can_update_status():
            return

        if not powered:
            if data.get("blocked"):
                self.set_status("Bluetooth is blocked (rfkill). Flip the switch to unblock it.")
            else:
                self.set_status("Bluetooth is off. Flip the switch to turn it on.")
        elif scan_state == "partial":
            self.set_status("Scanning for devices…", busy=True)
        else:
            connected = [d["name"] for d in self.devices if d["connected"]]
            if connected:
                self.set_status("Connected to %s" % ", ".join(connected), "ok")
            elif self.devices:
                self.set_status("%d devices · none connected" % len(self.devices))
            else:
                self.set_status("No devices found. Put your device in pairing mode and refresh.")

    # -- power ---------------------------------------------------------------------
    def _on_power(self, want):
        if self._power_busy:
            return
        self._power_busy = True
        self.pinned = False
        self._gen += 1  # drop scan results that are still on their way
        self.set_status("Turning Bluetooth %s…" % ("on" if want else "off"), busy=True)
        self.bg(self._power_worker, want)

    def _power_worker(self, want):
        if want:
            pc.run(["rfkill", "unblock", "bluetooth"], 5)
        message, ok = "", False
        for _ in range(4 if want else 1):  # the adapter can take a second to reappear
            try:
                adapter = adapter_path(pc.managed_objects(BLUEZ))
                if adapter is None:
                    message = "No default controller available"
                    time.sleep(1)
                    continue
                pc.dbus_set(BLUEZ, adapter, ADAPTER_IF, "Powered", GLib.Variant("b", want))
                ok = True
                break
            except GLib.Error as exc:
                message = pc.error_text(exc)
                break
        self.ui(self._power_done, want, ok, message)

    def _power_done(self, want, ok, message):
        self._power_busy = False
        if ok:
            self.refresh(scan=want, force=True)
            return
        self.pinned = True
        self.set_status(explain_failure(message, "Bluetooth", "turn on" if want else "turn off"),
                        "error")
        self.refresh(scan=False)  # snaps the switch back to the real state

    # -- rows ------------------------------------------------------------------------
    def _sync(self, devices):
        self.sync_rows(
            devices,
            key=lambda d: d["path"],
            make_row=self._row,
            state_of=lambda d: (d["connected"], d["paired"]),
            update_row=lambda row, dev: setattr(row, "dev", dev),
            order_of=lambda d: (0 if d["connected"] else 1 if d["paired"] else 2,
                                -d["rssi"], d["name"].lower()),
        )

    def _row(self, dev):
        row = Gtk.ListBoxRow()
        row.dev = dev
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
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

        if not dev["paired"]:
            meta = Gtk.Label(label="new")
            meta.get_style_context().add_class("meta")
            box.pack_start(meta, False, False, 0)

        if dev["paired"] and not dev["connected"]:
            box.pack_start(
                self.action_button("forget", lambda r=row: self._forget(r.dev)),
                False, False, 0)
        if dev["connected"]:
            box.pack_start(
                self.action_button("disconnect", lambda r=row: self._toggle(r.dev), primary=True),
                False, False, 0)
        else:
            label = "connect" if dev["paired"] else "pair"
            box.pack_start(
                self.action_button(label, lambda r=row: self._toggle(r.dev), primary=True),
                False, False, 0)
        return row

    def _on_row(self, _listbox, row):
        dev = getattr(row, "dev", None)
        if dev is not None:
            self._toggle(dev)

    # -- actions ---------------------------------------------------------------------------
    def _begin(self, text):
        self.busy = True
        self.pinned = False
        self.set_status(text, busy=True)

    def _after_action(self, message, ok):
        self.busy = False
        self.pinned = True  # keep this message until the user does something else
        self.set_status(message, "ok" if ok else "error")
        self.refresh(scan=False)

    def _toggle(self, dev):
        pc.log("clicked: %s (paired=%s connected=%s)" % (dev["name"], dev["paired"], dev["connected"]))
        if self.busy or self._power_busy:
            self.set_status("Still working on the last action, one moment…", busy=True)
            return
        if dev["connected"]:
            self._begin("Disconnecting from %s…" % dev["name"])
            self.bg(self._disconnect_worker, dev)
        else:
            verb = "Connecting to" if dev["paired"] else "Pairing with"
            self._begin("%s %s…" % (verb, dev["name"]))
            self.bg(self._connect_worker, dev)

    def _connect_worker(self, dev):
        path, mac, name = dev["path"], dev["mac"], dev["name"]
        if not dev["paired"]:
            _, out = bt("pair", mac, timeout=45)
            pc.log("pair %s -> %r" % (mac, out))
            low = out.lower()
            if "pairing successful" not in low and "already exists" not in low \
                    and "alreadyexists" not in low:
                self.ui(self._after_action, explain_failure(out, name, "pair with"), False)
                return
            self.ui(self.set_status, "Connecting to %s…" % name, "info", True)
        try:
            pc.dbus_set(BLUEZ, path, DEVICE_IF, "Trusted", GLib.Variant("b", True))
        except GLib.Error:
            pass
        try:
            pc.dbus_call(BLUEZ, path, DEVICE_IF, "Connect", timeout=30000)
        except GLib.Error as exc:
            pc.log("connect %s failed: %s" % (name, pc.error_text(exc)))
            self.ui(self._after_action,
                    explain_failure(pc.error_text(exc), name, "connect to"), False)
            return
        self.ui(self._after_action, "Connected to %s" % name, True)

    def _disconnect_worker(self, dev):
        try:
            pc.dbus_call(BLUEZ, dev["path"], DEVICE_IF, "Disconnect", timeout=15000)
        except GLib.Error as exc:
            self.ui(self._after_action,
                    explain_failure(pc.error_text(exc), dev["name"], "disconnect from"), False)
            return
        self.ui(self._after_action, "Disconnected from %s" % dev["name"], True)

    def _forget(self, dev):
        if self.busy or self._power_busy or not self.adapter:
            return
        self._begin("Forgetting %s…" % dev["name"])
        self.bg(self._forget_worker, dev, self.adapter)

    def _forget_worker(self, dev, adapter):
        try:
            pc.dbus_call(BLUEZ, adapter, ADAPTER_IF, "RemoveDevice",
                         GLib.Variant("(o)", (dev["path"],)))
        except GLib.Error as exc:
            self.ui(self._after_action,
                    explain_failure(pc.error_text(exc), dev["name"], "forget"), False)
            return
        self.ui(self._after_action, "Forgot %s" % dev["name"], True)


if __name__ == "__main__":
    pc.main("bluetooth", BluetoothPortal)
