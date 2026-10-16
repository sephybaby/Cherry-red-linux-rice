
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: root

    property bool dashboardOpen: true

    IpcHandler {
        target: "cherry-red"

        function toggle(): void {
            root.dashboardOpen = !root.dashboardOpen
        }
    }

    visible: root.dashboardOpen

    implicitWidth: 760
    implicitHeight: 540

    anchors {
        top: true
        right: true
    }

    margins {
        top: 60
        right: 20
    }

    color: "transparent"

    WlrLayershell.namespace: "cherry-red"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property string currentTab: "Widgets"

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: "#f2171016"
        border.color: "#593044"
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            Text {
                text: "Cherry Red"
                color: "#ffc0d2"
                font.pixelSize: 28
                font.bold: true
            }

            Text {
                text: "YOUR DESKTOP, YOUR SPACE"
                color: "#bd91a4"
                font.pixelSize: 11
                font.letterSpacing: 2
            }

            Row {
                spacing: 10

                Repeater {
                    model: ["Widgets", "Pins", "Kanban", "Wallpapers"]

                    delegate: Rectangle {
                        required property string modelData

                        width: 160
                        height: 42
                        radius: 12

                        color: root.currentTab === modelData
                            ? "#8c3657" : "#38202e"

                        border.color: root.currentTab === modelData
                            ? "#ffc0d2" : "#704056"

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: "#ffe5ed"
                            font.pixelSize: 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.currentTab = modelData
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#49303d"
            }

            Loader {
                width: parent.width
                height: 330

                sourceComponent: {
                    if (root.currentTab === "Widgets")
                        return widgetsPage
                    if (root.currentTab === "Pins")
                        return pinsPage
                    if (root.currentTab === "Kanban")
                        return kanbanPage
                    return wallpapersPage
                }
            }
        }
    }

    Component {
        id: widgetsPage

        Column {
            spacing: 14

            Text {
                text: "Your widgets 🍒"
                color: "#f6dce5"
                font.pixelSize: 21
            }

            Text {
                text: "Quick access to your desktop."
                color: "#bd91a4"
                font.pixelSize: 14
            }

            Text {
                text: "♫  Music player"
                color: "#ffc0d2"
                font.pixelSize: 17
            }

            Text {
                text: "▦  Calendar"
                color: "#ffc0d2"
                font.pixelSize: 17
            }

            Text {
                text: "☼  Brightness and volume"
                color: "#ffc0d2"
                font.pixelSize: 17
            }

            Text {
                text: "⌁  Network and Bluetooth"
                color: "#ffc0d2"
                font.pixelSize: 17
            }
        }
    }

    Component {
        id: pinsPage

        Column {
            spacing: 14

            Text {
                text: "Your Pins"
                color: "#f6dce5"
                font.pixelSize: 21
            }

            Text {
                text: "Your favourite apps will live here."
                color: "#bd91a4"
                font.pixelSize: 14
            }

            Text {
                text: "＋  App shortcuts coming next"
                color: "#ffc0d2"
                font.pixelSize: 16
            }
        }
    }

    Component {
        id: kanbanPage

        Column {
            spacing: 14

            Text {
                text: "Your Kanban"
                color: "#f6dce5"
                font.pixelSize: 21
            }

            Text {
                text: "A little space to organise your tasks."
                color: "#bd91a4"
                font.pixelSize: 14
            }

            Text {
                text: "○  To do"
                color: "#ffc0d2"
                font.pixelSize: 16
            }

            Text {
                text: "◷  In progress"
                color: "#ffc0d2"
                font.pixelSize: 16
            }

            Text {
                text: "✓  Done"
                color: "#ffc0d2"
                font.pixelSize: 16
            }
        }
    }

    Component {
        id: wallpapersPage

        Column {
            spacing: 14

            Text {
                text: "Wallpapers"
                color: "#f6dce5"
                font.pixelSize: 21
            }

            Text {
                text: "Your desktop, your aesthetic."
                color: "#bd91a4"
                font.pixelSize: 14
            }

            Text {
                text: "♡  Wallpaper browser coming next"
                color: "#ffc0d2"
                font.pixelSize: 16
            }
        }
    }
}

