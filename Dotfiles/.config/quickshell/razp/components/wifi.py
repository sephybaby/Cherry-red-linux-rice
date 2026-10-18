#!/usr/bin/env python3
"""Wi-Fi popup. Reads iwd over D-Bus (instant); iwctl is only used to connect."""
import os
import time

import portal_common as pc
from portal_common import GLib, Gtk, Pango

DEVICE = os.environ.get("WIFI_DEVICE", "wlan0")

IWD = "net.connman.iwd"
DEVICE_IF = "net.connman.iwd.Device"
STATION_IF = "net.connman.iwd.Station"
NETWORK_IF = "net.connman.iwd.Network"
KNOWN_IF = "net.connman.iwd.KnownNetwork"

BARS = ["▂", "▄", "▆", "█"]
SECURITY_TAG = {"open": "open", "8021x": "802.1x", "wep": "wep"}  # plain WPA shows nothing


# --------------------------------------------------------------------------
# iwd helpers
# --------------------------------------------------------------------------
def bars_from_signal(signal):
    """iwd reports signal in hundredths of a dBm."""
    dbm = signal / 100.0
    return 4 if dbm >= -55 else 3 if dbm >= -65 else 2 if dbm >= -75 else 1


def make_net(path, props, signal):
    return {
        "ssid": props.get("Name", "?"),
        "path": path,
        "connected": bool(props.get("Connected")),
        "known": "KnownNetwork" in props,
        "known_path": props.get("KnownNetwork"),
        "security": props.get("Type", "psk"),
        "bars": bars_from_signal(signal) if signal is not None else 0,
    }


def fetch():
    """Everything the window needs, in one dict:
    error, device, station, powered, nets, scanning."""
    data = {"error": None, "device": None, "station": None,
            "powered": False, "nets": [], "scanning": False}
    try:
        objs = pc.managed_objects(IWD)
    except GLib.Error as exc:
        data["error"] = ("Can't reach iwd (%s). Is the iwd service running?"
                         % pc.error_text(exc))
        return data

    for path, ifaces in objs.items():
        props = ifaces.get(DEVICE_IF)
        if props and props.get("Name") == DEVICE:
            data["device"] = path
            data["powered"] = bool(props.get("Powered")) and STATION_IF in ifaces
            if STATION_IF in ifaces:
                data["station"] = path
    if data["device"] is None:
        data["error"] = ("No Wi-Fi device called %s. Set WIFI_DEVICE if yours has another name."
                         % DEVICE)
        return data
    if data["station"] is None:
        return data  # adapter is switched off

    station = data["station"]
    state = objs[station][STATION_IF]
    data["scanning"] = bool(state.get("Scanning"))
    try:
        ordered = pc.dbus_call(IWD, station, STATION_IF, "GetOrderedNetworks").unpack()[0]
    except GLib.Error as exc:
        data["error"] = "Could not list networks: %s" % pc.error_text(exc)
        return data

    nets, seen = [], set()
    connected_path = state.get("ConnectedNetwork")
    for path, signal in ordered:
        props = objs.get(path, {}).get(NETWORK_IF)
        if not props:
            continue
        net = make_net(path, props, signal)
        net["connected"] = net["connected"] or path == connected_path
        nets.append(net)
        seen.add(path)
    if connected_path and connected_path not in seen:  # connected but not in the scan list
        props = objs.get(connected_path, {}).get(NETWORK_IF)
        if props:
            net = make_net(connected_path, props, None)
            net["connected"] = True
            nets.append(net)
    data["nets"] = nets
    return data


def connected_ssid():
    return next((n["ssid"] for n in fetch()["nets"] if n["connected"]), None)


def bars_markup(count):
    return "".join('<span alpha="%s">%s</span>' % ("100%" if i < count else "30%", ch)
                   for i, ch in enumerate(BARS))


def explain_connect_error(rc, out, net, had_password):
    ssid = net["ssid"]
    low = out.lower()
    if rc == 127:
        return "iwctl is not installed (package: iwd)."
    if rc == 124:
        return "Timed out waiting for %s. Move closer and try again." % ssid
    if "not found" in low or "no such" in low:
        return '"%s" is no longer visible. Refresh and try again.' % ssid
    if "in progress" in low:
        return "Another Wi-Fi operation is in progress. Wait a moment and retry."
    detail = out.splitlines()[-1].strip() if out.strip() else ""
    hint = ""
    if had_password:
        hint = " The password may be wrong."
    elif net["known"]:
        hint = ' The saved password may be outdated: use "forget" and try again.'
    return "Could not connect to %s%s.%s" % (
        ssid, " (%s)" % detail if detail else "", hint)


# --------------------------------------------------------------------------
# Window
# --------------------------------------------------------------------------
class WifiPortal(pc.Portal):
    def __init__(self):
        super().__init__("wifi", "Wi-Fi")
        self.device = None
        self.station = None
        self.pending = None
        self._power_busy = False
        self.hint.set_text("Press connect, or click a network")
        self.add_power_switch(self._on_power)
        self._build_password_prompt()
        self.listbox.connect("row-activated", self._on_row)
        self.refresh()

    # -- password prompt ---------------------------------------------------------
    def _build_password_prompt(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.get_style_context().add_class("password-box")

        self.pw_title = Gtk.Label(label="")
        self.pw_title.set_xalign(0)
        self.pw_title.get_style_context().add_class("password-title")

        self.pw_entry = Gtk.Entry()
        self.pw_entry.set_visibility(False)
        self.pw_entry.set_placeholder_text("Password")
        self.pw_entry.get_style_context().add_class("password-entry")
        self.pw_entry.connect("activate", lambda *_: self._submit_password())

        buttons = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        cancel = Gtk.Button(label="Cancel")
        cancel.get_style_context().add_class("password-cancel")
        cancel.connect("clicked", lambda *_: self._hide_prompt())
        connect = Gtk.Button(label="Connect")
        connect.get_style_context().add_class("password-connect")
        connect.connect("clicked", lambda *_: self._submit_password())
        buttons.pack_end(connect, False, False, 0)
        buttons.pack_end(cancel, False, False, 0)

        box.pack_start(self.pw_title, False, False, 0)
        box.pack_start(self.pw_entry, False, False, 0)
        box.pack_start(buttons, False, False, 0)

        self.revealer = Gtk.Revealer()
        self.revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_UP)
        self.revealer.add(box)
        self.extra.pack_start(self.revealer, False, False, 0)

    def _ask_password(self, net):
        self.pending = net
        self.pw_title.set_text('Password for "%s"' % net["ssid"])
        self.pw_entry.set_text("")
        self.revealer.set_reveal_child(True)
        self.pw_entry.grab_focus()
        self.pinned = True
        self.set_status('Type the password for "%s" below, then press Enter.' % net["ssid"])

    def _hide_prompt(self):
        self.pending = None
        self.pw_entry.set_text("")
        self.revealer.set_reveal_child(False)

    def _submit_password(self):
        password = self.pw_entry.get_text()
        net = self.pending
        if net is None or not password:
            return
        self._hide_prompt()
        self._begin("Connecting to %s…" % net["ssid"])
        self.bg(self._connect_worker, net, password)

    def on_escape(self):
        if self.revealer.get_reveal_child():
            self._hide_prompt()
            return True
        return False

    # -- power switch ----------------------------------------------------------------
    def _on_power(self, want):
        if self._power_busy or not self.device:
            return
        self._power_busy = True
        self.pinned = False
        self._gen += 1  # drop scan results that are still on their way
        self.set_status("Turning Wi-Fi %s…" % ("on" if want else "off"), busy=True)
        self.bg(self._power_worker, want, self.device)

    def _power_worker(self, want, device):
        if want:
            pc.run(["rfkill", "unblock", "wifi"], 5)
        try:
            pc.dbus_set(IWD, device, DEVICE_IF, "Powered", GLib.Variant("b", want))
        except GLib.Error as exc:
            pc.log("power %s failed: %s" % (want, pc.error_text(exc)))
            self.ui(self._power_done, want, False, pc.error_text(exc))
            return
        for _ in range(10):  # the station comes back a moment after powering on
            data = fetch()
            if data["powered"] == want:
                break
            time.sleep(0.5)
        self.ui(self._power_done, want, True, "")

    def _power_done(self, want, ok, message):
        self._power_busy = False
        if ok:
            if want:
                self.refresh(force=True)
            else:
                self._quick_refresh()
            return
        self.pinned = True
        low = message.lower()
        if "blocked" in low or "permitted" in low:
            message = "Wi-Fi is blocked by rfkill. Run: rfkill unblock wifi"
        self.set_status("Could not turn Wi-Fi %s: %s" % ("on" if want else "off", message),
                        "error")
        self._quick_refresh()  # snaps the switch back to the real state

    # -- refreshing ------------------------------------------------------------------
    def on_refresh(self):
        self.pinned = False
        self.refresh()

    def refresh(self, force=False):
        """Scan for networks. Never blocks clicking on a network."""
        if self.scanning and not force:
            return
        self._gen += 1
        self.scanning += 1
        if self.can_update_status():
            self.set_status("Scanning for networks…", busy=True)
        self.bg(self._scan_worker, self._gen)

    def _quick_refresh(self):
        self._gen += 1
        self.bg(self._quick_worker, self._gen)

    def _scan_worker(self, gen):
        # What iwd already knows shows up immediately, fresh scan results stream in after.
        data = fetch()
        scannable = data["station"] is not None and not data["error"]
        self.ui(self._apply, gen, data, "partial" if scannable else "final")
        if not scannable:
            return
        try:
            pc.dbus_call(IWD, data["station"], STATION_IF, "Scan")
        except GLib.Error:
            pass  # already scanning is fine
        for i in range(10):
            time.sleep(0.6)
            if gen != self._gen:
                break
            data = fetch()
            self.ui(self._apply, gen, data, "partial")
            if not data["scanning"] and i >= 2:
                break
        self.ui(self._apply, gen, fetch(), "final")

    def _quick_worker(self, gen):
        self.ui(self._apply, gen, fetch(), "none")

    def _apply(self, gen, data, scan_state):
        if scan_state == "final":
            self.scanning = max(0, self.scanning - 1)
        if gen != self._gen:
            return  # a newer refresh already redrew the list
        self.device = data["device"] or self.device
        self.station = data["station"]
        nets = data["nets"]
        self.set_switch(data["powered"], enabled=data["device"] is not None)
        self._sync(nets)
        if not self.can_update_status():
            return
        if data["error"]:
            self.set_status(data["error"], "error")
            return
        if not data["powered"]:
            self.set_status("Wi-Fi is off. Flip the switch to turn it on.")
            return
        if scan_state == "partial":
            self.set_status("Scanning for networks…", busy=True)
            return
        count = len(nets)
        current = next((n for n in nets if n["connected"]), None)
        word = "network" if count == 1 else "networks"
        if current:
            self.set_status("Connected to %s · %d %s" % (current["ssid"], count, word), "ok")
        elif count:
            self.set_status("%d %s nearby · not connected" % (count, word))
        else:
            self.set_status("No networks found. Try refresh.", "error")

    # -- rows ------------------------------------------------------------------------
    def _sync(self, nets):
        self.sync_rows(
            nets,
            key=lambda n: n["path"],
            make_row=self._row,
            state_of=lambda n: (n["connected"], n["known"], n["security"]),
            update_row=self._update_row,
            order_of=lambda n: (0 if n["connected"] else 1 if n["known"] else 2,
                                -n["bars"], n["ssid"].lower()),
        )

    @staticmethod
    def _update_row(row, net):
        row.net = net
        row.signal.set_markup(bars_markup(net["bars"]))

    def _row(self, net):
        row = Gtk.ListBoxRow()
        row.net = net
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add(box)
        if net["connected"]:
            row.get_style_context().add_class("connected")

        name = Gtk.Label(label=net["ssid"])
        name.set_xalign(0)
        name.set_ellipsize(Pango.EllipsizeMode.END)
        name.get_style_context().add_class("name")
        box.pack_start(name, True, True, 0)

        tag = SECURITY_TAG.get(net["security"])
        if tag:
            label = Gtk.Label(label=tag)
            label.get_style_context().add_class("meta")
            box.pack_start(label, False, False, 0)

        if net["known"] and not net["connected"]:
            box.pack_start(
                self.action_button("forget", lambda r=row: self._forget(r.net)),
                False, False, 0)
        if net["connected"]:
            box.pack_start(
                self.action_button("disconnect", self._disconnect, primary=True),
                False, False, 0)
        else:
            box.pack_start(
                self.action_button("connect", lambda r=row: self._connect(r.net), primary=True),
                False, False, 0)

        row.signal = Gtk.Label()
        row.signal.set_markup(bars_markup(net["bars"]))
        row.signal.get_style_context().add_class("signal")
        box.pack_start(row.signal, False, False, 0)
        return row

    def _on_row(self, _listbox, row):
        net = getattr(row, "net", None)
        if net is None:
            return
        if net["connected"]:
            self.pinned = True
            self.set_status("Already connected to %s" % net["ssid"], "ok")
        else:
            self._connect(net)

    # -- actions -----------------------------------------------------------------------
    def _begin(self, text):
        self.busy = True
        self.pinned = False
        self.set_status(text, busy=True)

    def _after_action(self, message, ok):
        self.busy = False
        self.pinned = True  # keep this message until the user does something else
        self.set_status(message, "ok" if ok else "error")
        self._quick_refresh()

    def _connect(self, net):
        pc.log("connect clicked: %s (%s, known=%s)" % (net["ssid"], net["security"], net["known"]))
        if self.busy:
            self.set_status("Still working on the last action, one moment…", busy=True)
            return
        if net["security"] == "8021x":
            self.pinned = True
            self.set_status(
                "%s is an enterprise (802.1x) network. Configure it in iwd first." % net["ssid"],
                "error")
        elif net["security"] == "open" or net["known"]:
            self._begin("Connecting to %s…" % net["ssid"])
            self.bg(self._connect_worker, net, None)
        else:
            self._ask_password(net)

    def _connect_worker(self, net, password):
        ssid = net["ssid"]
        cmd = ["iwctl"]
        if password is not None:
            cmd += ["--passphrase", password]
        rc, out = pc.run(cmd + ["station", DEVICE, "connect", ssid], 45)
        pc.log("iwctl connect %s -> rc=%s out=%r" % (ssid, rc, out))
        # Ask iwd what it is really connected to instead of trusting the exit code.
        connected = False
        for _ in range(4 if rc == 0 else 1):
            if connected_ssid() == ssid:
                connected = True
                break
            time.sleep(1)
        if connected:
            self.ui(self._after_action, "Connected to %s" % ssid, True)
        else:
            self.ui(self._after_action,
                    explain_connect_error(rc, out, net, password is not None), False)

    def _disconnect(self):
        if self.busy or not self.station:
            return
        self._begin("Disconnecting…")
        self.bg(self._disconnect_worker, self.station)

    def _disconnect_worker(self, station):
        try:
            pc.dbus_call(IWD, station, STATION_IF, "Disconnect")
        except GLib.Error as exc:
            self.ui(self._after_action, "Could not disconnect: %s" % pc.error_text(exc), False)
            return
        self.ui(self._after_action, "Disconnected", True)

    def _forget(self, net):
        if self.busy or not net.get("known_path"):
            return
        self._begin("Forgetting %s…" % net["ssid"])
        self.bg(self._forget_worker, net)

    def _forget_worker(self, net):
        try:
            pc.dbus_call(IWD, net["known_path"], KNOWN_IF, "Forget")
        except GLib.Error as exc:
            self.ui(self._after_action,
                    "Could not forget %s: %s" % (net["ssid"], pc.error_text(exc)), False)
            return
        self.ui(self._after_action,
                "Forgot %s. Press connect to add it again with a new password." % net["ssid"],
                True)


if __name__ == "__main__":
    pc.main("wifi", WifiPortal)
