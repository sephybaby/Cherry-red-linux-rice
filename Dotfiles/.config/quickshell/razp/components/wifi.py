#!/usr/bin/env python3
"""Wi-Fi popup (iwd / iwctl). Opened by clicking the Wi-Fi card in the dashboard."""
import os
import re
import time

import portal_common as pc
from portal_common import Gtk, Pango

DEVICE = os.environ.get("WIFI_DEVICE", "wlan0")

# "  >  My Network     psk      -4700"   (> marks the connected network)
ROW = re.compile(r"^\s*(>)?\s*(.+?)\s{2,}(psk|open|8021x|wep)\b\s*(.*)$", re.I)
BARS = ["▂", "▄", "▆", "█"]
SECURITY_LABEL = {"open": "open", "psk": "secured", "8021x": "802.1x", "wep": "wep"}


# --------------------------------------------------------------------------
# iwctl helpers
# --------------------------------------------------------------------------
def iwctl(*args, passphrase=None, timeout=15):
    cmd = ["iwctl"]
    if passphrase is not None:
        cmd += ["--passphrase", passphrase]
    return pc.run(cmd + list(args), timeout)


def signal_bars(rest):
    """0-4 bars from the signal column (dBm, or stars on old iwctl)."""
    match = re.search(r"-?\d+(?:\.\d+)?", rest)
    if match:
        dbm = float(match.group(0))
        if abs(dbm) > 200:  # iwd reports hundredths of a dBm
            dbm /= 100
        return 4 if dbm >= -55 else 3 if dbm >= -65 else 2 if dbm >= -75 else 1
    stars = rest.count("*")
    return max(1, min(4, stars)) if stars else 0


def parse_networks(text):
    found = {}
    for line in text.splitlines():
        match = ROW.match(line)
        if not match:
            continue
        ssid = match.group(2).strip()
        net = found.setdefault(
            ssid,
            {"ssid": ssid, "connected": False, "known": False,
             "security": match.group(3).lower(), "bars": 0},
        )
        net["connected"] = net["connected"] or bool(match.group(1))
        net["bars"] = max(net["bars"], signal_bars(match.group(4)))
    return list(found.values())


def fetch():
    """-> (returncode, raw output, networks) with `known` and `connected` filled in."""
    rc, out = iwctl("station", DEVICE, "get-networks", "rssi-dbms")
    nets = parse_networks(out)
    if not nets and rc != 0:  # older iwctl without rssi-dbms
        rc, out = iwctl("station", DEVICE, "get-networks")
        nets = parse_networks(out)
    known = {n["ssid"] for n in parse_networks(iwctl("known-networks", "list")[1])}
    current = current_ssid()  # the real answer, not the ">" marker in the table
    for net in nets:
        net["known"] = net["ssid"] in known
        if current:
            net["connected"] = net["ssid"] == current
    if current and not any(n["ssid"] == current for n in nets):
        # connected but not in the scan results (hidden / just out of range)
        nets.append({"ssid": current, "connected": True, "known": True,
                     "security": "psk", "bars": 0})
    return rc, out, nets


def current_ssid():
    """What iwd is *really* connected to (iwctl exit codes are unreliable)."""
    _, out = iwctl("station", DEVICE, "show")
    state = re.search(r"^\s*State\s+(\S+)", out, re.M)
    net = re.search(r"^\s*Connected network\s+(.+?)\s*$", out, re.M)
    if state and state.group(1) == "connected" and net:
        return net.group(1)
    return None


def explain_scan_error(rc, out):
    if rc == 127:
        return "iwctl is not installed (package: iwd)."
    if rc == 124:
        return "iwctl timed out. Is the iwd service running? (systemctl status iwd)"
    first = out.splitlines()[0].strip() if out.strip() else "iwctl returned an error"
    return "Could not list networks on %s: %s" % (DEVICE, first)


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
        self.networks = []
        self.pending = None
        self.hint.set_text("Click a network to connect")
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

    # -- refreshing ------------------------------------------------------------------
    def on_refresh(self):
        self.pinned = False
        self.refresh()

    def refresh(self):
        """Scan for networks. Never blocks clicking on a network."""
        if self.scanning:
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
        # Show what iwd already knows straight away, then scan for fresh results.
        rc, out, nets = fetch()
        failed = rc != 0 and not nets
        self.ui(self._apply, gen, rc, out, nets, "final" if failed else "partial")
        if failed:
            return
        pc.run(["iwctl", "station", DEVICE, "scan"], 20)
        time.sleep(2.5)
        rc, out, nets = fetch()
        self.ui(self._apply, gen, rc, out, nets, "final")

    def _quick_worker(self, gen):
        rc, out, nets = fetch()
        self.ui(self._apply, gen, rc, out, nets, "none")

    def _apply(self, gen, rc, out, nets, scan_state):
        if scan_state == "final":
            self.scanning = max(0, self.scanning - 1)
        if gen != self._gen:
            return  # a newer refresh already redrew the list
        self.networks = nets
        self._rebuild()
        if not self.can_update_status():
            return
        if rc != 0 and not nets:
            self.set_status(explain_scan_error(rc, out), "error")
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
            self.set_status("No networks found. Is Wi-Fi turned on? Try refresh.", "error")

    # -- rows ------------------------------------------------------------------------
    def _rebuild(self):
        self.clear_list()
        ordered = sorted(
            self.networks,
            key=lambda n: (not n["connected"], not n["known"], -n["bars"], n["ssid"].lower()),
        )
        for net in ordered:
            self.listbox.add(self._row(net))
        self.listbox.show_all()

    def _row(self, net):
        row = Gtk.ListBoxRow()
        row.net = net
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.add(box)
        if net["connected"]:
            row.get_style_context().add_class("connected")

        name = Gtk.Label(label=net["ssid"])
        name.set_xalign(0)
        name.set_ellipsize(Pango.EllipsizeMode.END)
        name.get_style_context().add_class("name")
        box.pack_start(name, True, True, 0)

        if net["connected"]:
            box.pack_start(self.action_button("disconnect", self._disconnect), False, False, 0)
        elif net["known"]:
            box.pack_start(
                self.action_button("forget", lambda n=net: self._forget(n)), False, False, 0)

        if net["connected"]:
            tag = Gtk.Label(label="connected")
        else:
            tag = Gtk.Label(label=SECURITY_LABEL.get(net["security"], net["security"]))
        tag.get_style_context().add_class("meta")
        box.pack_start(tag, False, False, 0)

        signal = Gtk.Label()
        signal.set_markup("".join(
            '<span alpha="%s">%s</span>' % ("100%" if i < net["bars"] else "30%", ch)
            for i, ch in enumerate(BARS)))
        signal.get_style_context().add_class("signal")
        box.pack_start(signal, False, False, 0)
        return row

    def _on_row(self, _listbox, row):
        net = getattr(row, "net", None)
        if net is None or self.busy:
            return
        if net["connected"]:
            self.pinned = True
            self.set_status("Already connected to %s" % net["ssid"], "ok")
        elif net["security"] == "8021x":
            self.pinned = True
            self.set_status(
                "%s is an enterprise (802.1x) network. Configure it in iwd first." % net["ssid"],
                "error")
        elif net["security"] == "open" or net["known"]:
            self._begin("Connecting to %s…" % net["ssid"])
            self.bg(self._connect_worker, net, None)
        else:
            self._ask_password(net)

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

    def _connect_worker(self, net, password):
        ssid = net["ssid"]
        rc, out = iwctl("station", DEVICE, "connect", ssid, passphrase=password, timeout=45)
        # Ask iwd what it is really connected to instead of trusting the exit code.
        connected = False
        for _ in range(4 if rc == 0 else 1):
            if current_ssid() == ssid:
                connected = True
                break
            time.sleep(1)
        if connected:
            self.ui(self._after_action, "Connected to %s" % ssid, True)
        else:
            self.ui(self._after_action,
                    explain_connect_error(rc, out, net, password is not None), False)

    def _disconnect(self):
        if self.busy:
            return
        self._begin("Disconnecting…")
        self.bg(self._disconnect_worker)

    def _disconnect_worker(self):
        rc, out = iwctl("station", DEVICE, "disconnect")
        still = current_ssid()
        if still:
            self.ui(self._after_action, "Still connected to %s. %s" % (still, out), False)
        else:
            self.ui(self._after_action, "Disconnected", True)

    def _forget(self, net):
        if self.busy:
            return
        self._begin("Forgetting %s…" % net["ssid"])
        self.bg(self._forget_worker, net["ssid"])

    def _forget_worker(self, ssid):
        rc, out = iwctl("known-networks", ssid, "forget")
        # iwctl exit codes are unreliable: check the saved-network list instead.
        _, listing = iwctl("known-networks", "list")
        if ssid in {n["ssid"] for n in parse_networks(listing)}:
            detail = out or "iwd did not remove it (exit code %d)" % rc
            self.ui(self._after_action, "Could not forget %s: %s" % (ssid, detail), False)
        else:
            self.ui(self._after_action,
                    "Forgot %s. Click it again to add it with a new password." % ssid, True)


if __name__ == "__main__":
    pc.main("wifi", WifiPortal)
