import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "components"

PanelWindow {
    id: root
    implicitWidth: 1300
    implicitHeight: 580
    anchors { top: true; left: true; right: true }
    margins { top: 10; left: 0; right: 0 }
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "razp-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property color panel: "#f2210207"
    property color surface: "#42030f"
    property color surfaceLight: "#6e0c1c"
    property color borderColor: "#240309"
    property color cherry: "#8f142b"
    property color pink: "#a8324a"
    property color muted: "#a96b7b"
    property color textColor: "#ffe8ee"
    property color hoverColor: "#58101d"

    // Folder holding wifi.py, bluetooth.py, portal_common.py, style.css
    property string portalDir: Quickshell.shellDir + "/components"

    property string currentTime: Qt.formatDateTime(new Date(), "hh:mm AP")
    property string currentDate: Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy")
    property string songTitle: "Checking Spotify…"
    property string songArtist: ""
	property string wifiState: "Checking…"
	property string wifiNetwork: "Finding network…"
	property string wifiSignal: "-- dBm"
	property string wifiDownload: "-- Mbps"
	property string wifiUpload: "-- Mbps"
    property string batteryState: "Battery"
    property string volumeState: "Volume"
    property string brightnessState: "Brightness"
    property string profileState: "balanced"
    property string bluetoothState: "Bluetooth"
    property string musicStatus: ""

    function runProcess(proc) {
        // Quickshell Process is controlled through its running property.
        proc.running = false
        proc.running = true
    }

    property int brightnessTarget: 50
    property int volumeTarget: 50

    function setBrightness(v) {
        root.brightnessTarget = Math.max(1, v)      // never fully black
        root.brightnessState = root.brightnessTarget + "%"
        if (!brightnessTimer.running) brightnessTimer.start()
    }

    function setVolume(v) {
        root.volumeTarget = v
        root.volumeState = v + "%"
        if (!volumeTimer.running) volumeTimer.start()
    }

    function refreshSystem() {
		runProcess(wifiProcess)
		runProcess(wifiDetailsProcess)
		runProcess(wifiSpeedProcess)
        runProcess(bluetoothProcess)
        runProcess(batteryProcess)
        runProcess(volumeProcess)
        runProcess(brightnessProcess)
        runProcess(profileProcess)
        runProcess(spotifyMetadata)
        runProcess(spotifyStatus)
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.currentTime = Qt.formatDateTime(new Date(), "hh:mm AP")
            root.currentDate = Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy")
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refreshSystem()
    }

	Process {
    id: wifiProcess
    command: ["sh", "-lc", "nmcli -t -f GENERAL.STATE device show wlan0 2>/dev/null | head -n1"]
    stdout: StdioCollector {
        onStreamFinished: {
            var result = text.trim()
            root.wifiState = result.indexOf("100") >= 0
                ? "Connected"
                : result.indexOf("connecting") >= 0
                    ? "Connecting"
                    : "Disconnected"
        }
    }
}

Process {
    id: wifiDetailsProcess

    command: [
        "sh", "-lc",
        "printf '%s|' \"$(nmcli -g GENERAL.CONNECTION device show wlan0 2>/dev/null)\"; iw dev wlan0 link 2>/dev/null | awk '/signal:/ {print $2; exit}'"
    ]

    stdout: StdioCollector {
        onStreamFinished: {
            var result = text.trim().split("|")

            var network = result.length > 0 ? result[0].trim() : ""
            var signal = result.length > 1 ? result[1].trim() : ""

            root.wifiNetwork =
                network !== "" && network !== "--"
                ? network
                : "Not connected"

            root.wifiSignal =
                signal !== "" && !isNaN(Number(signal))
                ? signal + " dBm"
                : "-- dBm"
        }
    }
}


	Process {
		id: wifiSpeedProcess
		command: ["sh", "-lc",
			"rx1=$(cat /sys/class/net/wlan0/statistics/rx_bytes); tx1=$(cat /sys/class/net/wlan0/statistics/tx_bytes); sleep 1; rx2=$(cat /sys/class/net/wlan0/statistics/rx_bytes); tx2=$(cat /sys/class/net/wlan0/statistics/tx_bytes); awk -v a=\"$rx1\" -v b=\"$rx2\" -v c=\"$tx1\" -v d=\"$tx2\" 'BEGIN {printf \"%.1f|%.1f\", (b-a)*8/1000000, (d-c)*8/1000000}'"
		]
		stdout: StdioCollector {
			onStreamFinished: {
				var parts = text.trim().split("|")
				if (parts.length >= 2) {
					root.wifiDownload = parts[0] + " Mbps"
					root.wifiUpload = parts[1] + " Mbps"
				}
			}
		}
	}
    Process {
        id: bluetoothProcess
        command: ["sh", "-lc", "bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/ {print $2; exit}'"]
        stdout: StdioCollector { onStreamFinished: root.bluetoothState = text.trim() === "yes" ? "On" : "Off" }
    }
    Process {
        id: batteryProcess
        command: ["sh", "-lc", "if [ -r /sys/class/power_supply/BAT0/capacity ]; then cat /sys/class/power_supply/BAT0/capacity; else echo '--'; fi"]
        stdout: StdioCollector { onStreamFinished: root.batteryState = text.trim() + (text.trim() === "--" ? "" : "%") }
    }
    Process {
        id: volumeProcess
        command: ["sh", "-lc", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf \"%d%%\", $2*100}'"]
        stdout: StdioCollector { onStreamFinished: if (!volumeSlider.dragging) root.volumeState = text.trim() === "" ? "N/A" : text.trim() }
    }
    Process {
        id: brightnessProcess
        command: ["sh", "-lc", "b=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'); [ -n \"$b\" ] && echo \"$b%\" || echo N/A"]
        stdout: StdioCollector { onStreamFinished: if (!brightnessSlider.dragging) root.brightnessState = text.trim() }
    }
    Process {
        id: profileProcess
        command: ["sh", "-lc", "powerprofilesctl get 2>/dev/null || echo balanced"]
        stdout: StdioCollector { onStreamFinished: root.profileState = text.trim() }
    }
    Process {
        id: spotifyMetadata
        command: ["sh", "-lc", "playerctl metadata --format '{{title}}|{{artist}}' 2>/dev/null || echo 'Nothing playing|' "]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split("|")
                root.songTitle = parts.length > 0 && parts[0] !== "" ? parts[0] : "Nothing playing"
                root.songArtist = parts.length > 1 ? parts[1] : ""
            }
        }
    }
    Process {
        id: spotifyStatus
        command: ["sh", "-lc", "playerctl status 2>/dev/null || echo Stopped"]
        stdout: StdioCollector { onStreamFinished: root.musicStatus = text.trim() }
    }

    Item {
        anchors.fill: parent

        Rectangle {
            id: board
            width: 1300
            height: 556
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            radius: 28
            color: root.panel
            border.width: 1
            border.color: root.borderColor
            clip: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // LEFT: tall music card with circular artwork and controls
                MusicCard {
                    Layout.preferredWidth: 330
                    Layout.fillHeight: true
                    cherry: root.cherry
                    pink: root.pink
                    muted: root.muted
                    textColor: root.textColor
                    surface: root.surface
                    surfaceLight: root.surfaceLight
                    borderColor: root.borderColor
                    hoverColor: root.hoverColor
                }

                // RIGHT: exact sketch structure — status row, sliders, calendar + apps
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 104
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 205
                            Layout.fillHeight: true
                            radius: 16
                            color: root.surface
                            border.color: root.borderColor
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 3
                                Text { text: "TIME · DAY · DATE"; color: root.muted; font.pixelSize: 9; font.letterSpacing: 1 }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.currentTime
                                    color: root.textColor
                                    font.pixelSize: 29
                                    font.bold: true
                                    minimumPixelSize: 20
                                    fontSizeMode: Text.Fit
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.currentDate
                                    color: root.pink
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 16
                            color: root.surface
                            border.color: root.borderColor
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 5
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "⌁"; color: root.cherry; font.pixelSize: 22 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { text: "WI-FI"; color: root.muted; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.wifiNetwork
                                            color: root.textColor
                                            font.pixelSize: 13
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Text { text: root.wifiState; color: root.pink; font.pixelSize: 9 }
                                }
                                Rectangle { Layout.fillWidth: true; height: 1; color: root.borderColor }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: root.wifiSignal; color: root.muted; font.pixelSize: 10 }
                                    Item { Layout.fillWidth: true }
                                    Text { text: "↓ " + root.wifiDownload; color: root.textColor; font.pixelSize: 10 }
                                    Text { text: "↑ " + root.wifiUpload; color: root.textColor; font.pixelSize: 10 }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runProcess(wifiPortal)
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 112
                            Layout.fillHeight: true
                            radius: 16
                            color: root.surface
                            border.color: root.borderColor
                            Column {
                                anchors.centerIn: parent
                                spacing: 7
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ᛒ"; color: root.cherry; font.pixelSize: 25 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "BLUETOOTH"; color: root.muted; font.pixelSize: 8; font.letterSpacing: 1 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.bluetoothState; color: root.textColor; font.pixelSize: 11 }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => root.runProcess(mouse.button === Qt.RightButton ? bluetoothToggle : bluetoothPortal)
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 154
                            Layout.fillHeight: true
                            radius: 16
                            color: root.surface
                            border.color: root.borderColor
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 5
                                Text { text: "POWER PROFILE"; color: root.muted; font.pixelSize: 8; font.letterSpacing: 1 }
                                Repeater {
                                    model: [
                                        { label: "SAVE", value: "power-saver" },
                                        { label: "BALANCED", value: "balanced" },
                                        { label: "PERF", value: "performance" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 7
                                        color: root.profileState === modelData.value ? root.surfaceLight : "transparent"
                                        border.color: root.profileState === modelData.value ? root.cherry : root.borderColor
                                        Text { anchors.centerIn: parent; text: modelData.label; color: root.textColor; font.pixelSize: 9 }
                                        Process { id: profileSetter; command: ["powerprofilesctl", "set", modelData.value] }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                root.runProcess(profileSetter)
                                                root.profileState = modelData.value
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Brightness and volume are full-width horizontal controls
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 43
                        radius: 13
                        color: root.surface
                        border.color: root.borderColor
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12
                            Text { text: "☼"; color: root.cherry; font.pixelSize: 21 }
                            Text { text: "BRIGHTNESS"; color: root.muted; font.pixelSize: 9; font.letterSpacing: 1 }
                            HSlider {
                                id: brightnessSlider
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                value: parseInt(root.brightnessState) || 0
                                trackColor: root.borderColor
                                fillColor: root.cherry
                                handleColor: root.textColor
                                onMoved: v => root.setBrightness(v)
                            }
                            Text { text: root.brightnessState; color: root.textColor; font.pixelSize: 11 }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 43
                        radius: 13
                        color: root.surface
                        border.color: root.borderColor
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12
                            Text {
                                text: "◖"; color: root.cherry; font.pixelSize: 20
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.runProcess(volumeToggle) }
                            }
                            Text { text: "VOLUME"; color: root.muted; font.pixelSize: 9; font.letterSpacing: 1 }
                            HSlider {
                                id: volumeSlider
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                value: parseInt(root.volumeState) || 0
                                trackColor: root.borderColor
                                fillColor: root.cherry
                                handleColor: root.textColor
                                onMoved: v => root.setVolume(v)
                            }
                            Text { text: root.volumeState; color: root.textColor; font.pixelSize: 11 }
                        }
                    }

                    // Bottom row: calendar, four shortcuts, and the dark side band
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        CalendarCard {
                            Layout.preferredWidth: 330
                            Layout.fillHeight: true
                            cherry: root.cherry
                            pink: root.pink
                            muted: "#a96b7b"
                            textColor: root.textColor
                            surface: root.surface
                            borderColor: root.borderColor
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 2
                            columnSpacing: 9
                            rowSpacing: 9

                            Repeater {
                                model: [
                                    { label: "Terminal", icon: ">_", command: "kitty" },
                                    { label: "Zen", icon: "♡", command: "flatpak run app.zen_browser.zen" },
                                    { label: "Obsidian", icon: "✧", command: "obsidian" },
                                    { label: "Files", icon: "▤", command: "thunar || dolphin || xdg-open \"$HOME\"" }
                                ]
                                delegate: Rectangle {
                                    id: appTile
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 13
                                    color: tileMouse.containsMouse ? root.hoverColor : root.surface
                                    border.color: root.borderColor
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: appTile.modelData.icon; color: root.cherry; font.pixelSize: 24 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: appTile.modelData.label; color: root.textColor; font.pixelSize: 11 }
                                    }
                                    Process { id: launchApp; command: ["sh", "-lc", appTile.modelData.command] }
                                    MouseArea {
                                        id: tileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.runProcess(launchApp)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 42
                            Layout.fillHeight: true
                            radius: 12
                            color: "#240309"
                            border.color: "#300610"
                        }
                    }
                }
            }
        }
    }

    // Media actions
    Process { id: previousTrack; command: ["playerctl", "previous"] }
    Process { id: toggleTrack; command: ["playerctl", "play-pause"] }
    Process { id: nextTrack; command: ["playerctl", "next"] }
    // Popups: setsid so they outlive the click; a second click toggles them closed.
    Process { id: wifiPortal; command: ["sh", "-c", "setsid -f python3 \"" + root.portalDir + "/wifi.py\" >>/tmp/portal-wifi.log 2>&1"] }
    Process { id: bluetoothPortal; command: ["sh", "-c", "setsid -f python3 \"" + root.portalDir + "/bluetooth.py\" >>/tmp/portal-bluetooth.log 2>&1"] }
    Process { id: bluetoothToggle; command: ["sh", "-lc", "if bluetoothctl show | grep -q 'Powered: yes'; then bluetoothctl power off; else bluetoothctl power on; fi"] }
    Timer { id: brightnessTimer; interval: 50; onTriggered: root.runProcess(brightnessSet) }
    Timer { id: volumeTimer; interval: 50; onTriggered: root.runProcess(volumeSet) }
    Process { id: brightnessSet; command: ["brightnessctl", "set", root.brightnessTarget + "%"] }
    Process { id: volumeSet; command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (root.volumeTarget / 100).toFixed(2)] }
    Process { id: volumeToggle; command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"] }
    Process { id: brightnessUp; command: ["brightnessctl", "set", "+5%"] }
    Process { id: refreshAfterAction; command: ["true"] }

    Component.onCompleted: root.refreshSystem()
}

