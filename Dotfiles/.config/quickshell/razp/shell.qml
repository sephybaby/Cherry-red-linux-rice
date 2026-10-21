//@ pragma NoReloadPopup
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
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
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property color panel: "#f2210207"
    property color surface: "#42030f"
    property color surfaceLight: "#6e0c1c"
    property color borderColor: "#240309"
    property color cherry: "#8f142b"
    property color pink: "#a8324a"
    property color muted: "#a96b7b"
    property color textColor: "#ffe8ee"
    property color hoverColor: "#58101d"

    // connection to obsidian 
    property string todoFolder: "/home/sephy/Obsidian/Uni/System/To-Dos"

    // quotes 
    property string quoteFile: "/home/sephy/Obsidian/Uni/System/Life Lessons & Quotes.md"

    property bool shown: false
    onShownChanged: { if (shown) refreshSystem(); else lastHidden = Date.now() }

    property bool toolOpen: wifiTool.running || bluetoothTool.running
    visible: shown && !toolOpen

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: root.shown = false
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.shown && !root.toolOpen
        onCleared: root.shown = false
    }

    property real lastHidden: 0

    IpcHandler {
        target: "razp"
        function toggle(): void {
            if (root.shown) root.shown = false
            else if (Date.now() - root.lastHidden > 400) root.shown = true
        }
        function show(): void { root.shown = true }
        function hide(): void { root.shown = false }
    }

    function toolCommand(bin, hint) {
        var theme = Quickshell.shellDir + "/popup-theme"
        return ["sh", "-c",
                "command -v " + bin + " >/dev/null || exec kitty -e sh -c 'echo \"" + hint + "\"; read -r _'; " +
                "exec env XDG_CONFIG_HOME=\"" + theme + "\" GTK_THEME=Adwaita:dark " + bin]
    }

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
    property string batteryPercent: "--"
    property bool batteryCharging: false
    property string volumeState: "Volume"
    property string brightnessState: "Brightness"
    property string profileState: "balanced"
    property string bluetoothState: "Bluetooth"
    property string bluetoothDevice: "Not connected"
    property string musicStatus: ""

    function profileLabel(value) {
        return value === "power-saver" ? "Power saving" : value === "performance" ? "performance" : "balanced"
    }

    function runProcess(proc) {
        proc.running = false
        proc.running = true
    }

    property int brightnessTarget: 50
    property int volumeTarget: 50

    function setBrightness(v) {
        root.brightnessTarget = Math.max(1, v)      
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
        runProcess(bluetoothDeviceProcess)
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
        running: root.shown
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
        id: bluetoothDeviceProcess
        command: ["sh", "-lc", "bluetoothctl devices Connected 2>/dev/null | head -n1 | cut -d' ' -f3-"]
        stdout: StdioCollector { onStreamFinished: root.bluetoothDevice = text.trim() !== "" ? text.trim() : "Not connected" }
    }
    Process {
        id: batteryProcess
        command: ["sh", "-lc", "b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1); if [ -n \"$b\" ]; then printf '%s|%s' \"$(cat $b/capacity)\" \"$(cat $b/status)\"; else printf '%s|%s' '--' 'None'; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim().split("|")
                root.batteryPercent = (p[0] === "" || p[0] === "--") ? "--" : p[0] + "%"
                root.batteryCharging = p.length > 1 && p[1] === "Charging"
                root.batteryState = root.batteryPercent
            }
        }
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

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 106
                        Layout.maximumHeight: 106
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
                                Text { text: "Time"; color: root.muted; font.pixelSize: 12; font.letterSpacing: 1 }
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
                                    color: root.textColor
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 230
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
                                        Text { text: "Wi-Fi"; color: root.muted; font.pixelSize: 12; font.letterSpacing: 1 }
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
                                                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.runProcess(wifiTool)
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 230
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
                                    Text { text: ""; color: root.cherry; font.pixelSize: 22 }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { text: "Bluetooth"; color: root.muted; font.pixelSize: 9; font.letterSpacing: 1 }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.bluetoothDevice
                                            color: root.textColor
                                            font.pixelSize: 13
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Text { text: root.bluetoothState; color: root.pink; font.pixelSize: 9 }
                                }
                                                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => root.runProcess(mouse.button === Qt.RightButton ? bluetoothToggle : bluetoothTool)
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 200
                            Layout.fillHeight: true
                            radius: 16
                            color: root.surface
                            border.color: root.borderColor
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 11
                                spacing: 4
                                Text {
                                    text: "Battery · " + root.profileLabel(root.profileState)
                                    color: root.muted
                                    font.pixelSize: 9
                                    font.letterSpacing: 1
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 20
                                    Text { text: root.batteryPercent; color: root.textColor; font.pixelSize: 26; font.bold: true }
                                    Text {
                                        visible: root.batteryCharging
                                        text: ""
                                        color: root.textColor
                                        font.pixelSize: 20
                                        Layout.alignment: Qt.AlignBottom
                                        Layout.bottomMargin: 3
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { icon: "", value: "power-saver" },
                                            { icon: "", value: "balanced" },
                                            { icon: "", value: "performance" }
                                        ]
                                        delegate: Rectangle {
                                            id: modeButton
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            radius: 9
                                            color: root.profileState === modelData.value
                                                   ? root.cherry
                                                   : (modeMouse.containsMouse ? root.hoverColor : root.borderColor)
                                            border.color: root.profileState === modelData.value ? root.pink : "transparent"
                                            Text { anchors.centerIn: parent; text: modeButton.modelData.icon; color: root.textColor; font.pixelSize: 15 }
                                            Process { id: modeSetter; command: ["powerprofilesctl", "set", modeButton.modelData.value] }
                                            MouseArea {
                                                id: modeMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.profileState = modeButton.modelData.value
                                                    root.runProcess(modeSetter)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 43
                        Layout.maximumHeight: 43
                        spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        radius: 13
                        color: root.surface
                        border.color: root.borderColor
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
							spacing: 12

							Text { 
								readonly property var icons: ["","","","","","","","","","","","","","",""]
            
							 text: {
									let pct = brightnessSlider.value;
								    let index = Math.floor((pct / 100) * (icons.length - 1));
									return icons[Math.max(0, Math.min(index, icons.length - 1))];
								}
            
							color: root.textColor 
							font.pixelSize: 25 
							font.family: "JetBrainsMono Nerd Font"
							}

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
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        radius: 13
                        color: root.surface
                        border.color: root.borderColor
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 12
                            Text {
                                text: "󰋋"; color: root.textColor; font.pixelSize: 20
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.runProcess(volumeToggle) }
                            }
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

                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 10

                        CalendarCard {
                            Layout.preferredWidth: 300
                            Layout.fillHeight: true
                            cherry: root.cherry
                            pink: root.pink
                            muted: "#a96b7b"
                            textColor: root.textColor
                            surface: root.surface
                            borderColor: root.borderColor
                        }

                        GridLayout {
                            Layout.preferredWidth: 224
                            Layout.fillHeight: true
                            columns: 2
                            rowSpacing: 10
                            columnSpacing: 10
                            uniformCellWidths: true
                            uniformCellHeights: true

                            Repeater {
                                model: [
                                    { label: "Terminal", icon: "", command: "kitty" },
                                    { label: "Obsidian", icon: "✶", command: "obsidian" },
                                    { label: "Files", icon: "🗋", command: "thunar || dolphin || nautilus || xdg-open \"$HOME\"" },
                                    { label: "Zen", icon: "", command: "flatpak run app.zen_browser.zen" },
                                    { label: "Vesktop", icon: "", command: "vesktop || flatpak run dev.vencord.Vesktop" },
                                    { label: "Spotify", icon: "", command: "spotify-launcher || spotify || flatpak run com.spotify.Client" }
                                ]
                                delegate: Rectangle {
                                    id: appTile
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: 14
                                    color: tileMouse.containsMouse ? root.hoverColor : root.surface
                                    border.color: root.borderColor
                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: appTile.modelData.icon; color: root.textColor; font.pixelSize: 24 }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: appTile.modelData.label; color: root.textColor; font.pixelSize: 11 }
                                    }
                                    Process { id: launchApp; command: ["sh", "-lc", appTile.modelData.command] }
                                    MouseArea {
                                        id: tileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.runProcess(launchApp)
                                            root.shown = false
                                        }
                                    }
                                }
                            }
                        }

                        TodoCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 150
                            folder: root.todoFolder
                            cherry: root.cherry
                            pink: root.pink
                            muted: root.muted
                            textColor: root.textColor
                            surface: root.surface
                            surfaceLight: root.surfaceLight
                            borderColor: root.borderColor
                            hoverColor: root.hoverColor
                        }
                    }

                    QuoteBar {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: 48
                        Layout.maximumHeight: 48
                        filePath: root.quoteFile
                        cherry: root.cherry
                        pink: root.pink
                        muted: root.muted
                        textColor: root.textColor
                        surface: root.surface
                        borderColor: root.borderColor
                        hoverColor: root.hoverColor
                    }
                }
            }
        }
    }

    Process { id: previousTrack; command: ["playerctl", "previous"] }
    Process { id: toggleTrack; command: ["playerctl", "play-pause"] }
    Process { id: nextTrack; command: ["playerctl", "next"] }
    Process { id: wifiTool; command: root.toolCommand("iwgtk", "iwgtk is not installed. Install it with: yay -S iwgtk") }
    Process { id: bluetoothTool; command: root.toolCommand("blueman-manager", "blueman is not installed. Install it with: sudo pacman -S blueman") }
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

