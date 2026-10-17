
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root

    implicitWidth: 340
    implicitHeight: 180

    property color cherry: "#ff173f"
    property color pink: "#f0a0b8"
    property color muted: "#a47d8c"
    property color textColor: "#f4dfe6"
    property color surface: "#24171f"
    property color surfaceLight: "#30202a"
    property color borderColor: "#50303e"
    property color hoverColor: "#54303f"

    property string songTitle: "Checking Spotify..."
    property string songArtist: ""
    property string artUrl: ""
    property string musicStatus: ""

    color: surface
    radius: 15
    border.width: 1
    border.color: borderColor
    clip: true

    gradient: Gradient {
        GradientStop { position: 0.0; color: "#30202a" }
        GradientStop { position: 1.0; color: "#1d1118" }
    }

    function runProcess(proc) {
        if (proc.running)
            return
        proc.running = true
    }

    function refreshMusic() {
        runProcess(metadataProcess)
        runProcess(statusProcess)
    }

    Process {
        id: metadataProcess

        command: [
            "sh", "-lc",
            "playerctl metadata --format '{{title}}|{{artist}}|{{mpris:artUrl}}' 2>/dev/null || echo 'Nothing playing||'"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.trim().split("|")

                root.songTitle =
                    parts.length > 0 && parts[0] !== ""
                    ? parts[0] : "Nothing playing"

                root.songArtist =
                    parts.length > 1 ? parts[1] : ""

                var newArtUrl =
                    parts.length > 2 ? parts[2] : ""

                if (root.artUrl !== newArtUrl)
                    root.artUrl = newArtUrl
            }
        }
    }

    Process {
        id: statusProcess

        command: [
            "sh", "-lc",
            "playerctl status 2>/dev/null || echo Stopped"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                root.musicStatus = text.trim()
            }
        }
    }

    Process { id: previousTrack; command: ["playerctl", "previous"] }
    Process { id: toggleTrack; command: ["playerctl", "play-pause"] }
    Process { id: nextTrack; command: ["playerctl", "next"] }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refreshMusic()
    }

    Component.onCompleted: root.refreshMusic()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "NOW PLAYING"
            color: root.cherry
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 2
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 180
            spacing: 10

			
		Item {
			id: artworkFrame

			Layout.alignment: Qt.AlignHCenter
			Layout.preferredWidth: Math.min(220, parent.width)
			Layout.preferredHeight: Math.min(220, parent.width)
			width: Math.min(220, parent.width)
			height: width

			Item {
				id: vinylRecord
				anchors.fill: parent

				// Vinyl disc
				Rectangle {
					anchors.fill: parent
					radius: width / 2
					color: "#100208"
					border.width: 3
					border.color: root.borderColor
				}

				// Circular album artwork
				Item {
					id: artworkMask
					anchors.fill: parent
					anchors.margins: 13

					Image {
						id: artwork
						anchors.fill: parent
						source: root.artUrl
						fillMode: Image.PreserveAspectCrop
						asynchronous: true
						cache: true
						smooth: true
						visible: false
					}

					Rectangle {
						id: roundMask
						anchors.fill: parent
						radius: width / 2
						color: "white"
						visible: false
					}

					OpacityMask {
						anchors.fill: parent
						source: artwork
						maskSource: roundMask
						visible: artwork.status === Image.Ready
					}

					Rectangle {
						anchors.fill: parent
						radius: width / 2
						color: "#240309"
						visible: artwork.status !== Image.Ready
					}
				}

				// Vinyl grooves
				Repeater {
					model: 3

					delegate: Rectangle {
						required property int index

						anchors.centerIn: parent
						width: parent.width - 28 - index * 16
						height: width
						radius: width / 2
						color: "transparent"
						border.width: 1
						border.color: "#45f0a0b8"
					}
				}

				// Centre label
				Rectangle {
					anchors.centerIn: parent
					width: 38
					height: 38
					radius: width / 2
					color: "#450813"
					border.color: "#b51f42"
					border.width: 2

					Rectangle {
						anchors.centerIn: parent
						width: 7
						height: 7
						radius: width / 2
						color: "#f5dce3"
					}
				}
			}

			// One complete rotation every 8 seconds while playing
			RotationAnimation {
				target: vinylRecord
				from: 0
				to: 360
				duration: 8000
				loops: Animation.Infinite
				running: root.musicStatus === "Playing"
			}

			// Fallback when artwork is unavailable
			Column {
				anchors.centerIn: parent
				spacing: 5
				visible: artwork.status !== Image.Ready

				Text {
					anchors.horizontalCenter: parent.horizontalCenter
					text: "♫"
					color: root.cherry
					font.pixelSize: 48
				}

				Text {
					anchors.horizontalCenter: parent.horizontalCenter
					text: "CHERRY MUSIC"
					color: root.muted
					font.pixelSize: 9
					font.letterSpacing: 1
				}
			}

			// Playback status indicator
			Rectangle {
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				anchors.margins: 5
				width: 10
				height: 10
				radius: 5
				color: root.musicStatus === "Playing"
					? root.cherry : root.muted
				border.width: 1
				border.color: "#55ffffff"
			}
		}



        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.songTitle
                color: root.textColor
                font.pixelSize: 16
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            Text {
                Layout.fillWidth: true
                text: root.songArtist || "Waiting for artist..."
                color: root.muted
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            Repeater {
                model: [
                    { label: "‹", action: "previous" },
                    { label: root.musicStatus === "Playing" ? "Ⅱ" : "▶", action: "toggle" },
                    { label: "›", action: "next" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.preferredWidth: modelData.action === "toggle" ? 48 : 42
                    Layout.preferredHeight: 38
                    radius: 12
                    color: buttonMouse.containsMouse
                        ? root.hoverColor
                        : (modelData.action === "toggle" ? root.surfaceLight : "transparent")
                    border.width: 1
                    border.color: modelData.action === "toggle" ? root.cherry : root.borderColor

                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.textColor
                        font.pixelSize: 21
                        font.bold: true
                    }

                    MouseArea {
                        id: buttonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.action === "previous")
                                root.runProcess(previousTrack)
                            else if (modelData.action === "toggle")
                                root.runProcess(toggleTrack)
                            else
                                root.runProcess(nextTrack)
                        }
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.musicStatus === "" ? "SPOTIFY" : root.musicStatus.toUpperCase()
            color: root.muted
            font.pixelSize: 8
            font.letterSpacing: 2
        }
    }
}
}

