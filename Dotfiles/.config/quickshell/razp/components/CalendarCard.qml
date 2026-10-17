
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property color cherry: "#ff4566"
    property color pink: "#f078b8"
    property color muted: "#b98d9a"
    property color textColor: "#ffe8ee"
    property color surface: "#241016"
    property color borderColor: "#63303f"

    property date shownDate: new Date()
    property int year: shownDate.getFullYear()
    property int month: shownDate.getMonth()

    implicitWidth: 280
    implicitHeight: 270
    radius: 20
    color: surface
    border.color: borderColor
    border.width: 1

    function monthName(m) {
        return ["January", "February", "March", "April",
                "May", "June", "July", "August",
                "September", "October", "November", "December"][m]
    }

    function changeMonth(amount) {
        shownDate = new Date(year, month + amount, 1)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                spacing: 2

                Text {
                    text: root.monthName(root.month)
                    color: root.textColor
                    font.pixelSize: 19
                    font.bold: true
                }

                Text {
                    text: String(root.year)
                    color: root.muted
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: 10
                color: prevMouse.containsMouse ? "#63303f" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: root.textColor
                    font.pixelSize: 24
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.changeMonth(-1)
                }
            }

            Rectangle {
                implicitWidth: 30
                implicitHeight: 30
                radius: 10
                color: nextMouse.containsMouse ? "#63303f" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    color: root.textColor
                    font.pixelSize: 24
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.changeMonth(1)
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            columnSpacing: 3
            rowSpacing: 7

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]

                Text {
                    required property string modelData
                    text: modelData
                    color: root.pink
                    font.pixelSize: 10
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }
            }

            Repeater {
                model: {
                    const first = new Date(root.year, root.month, 1).getDay()
                    const count = new Date(root.year, root.month + 1, 0).getDate()
                    return first + count
                }

                Item {
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: 25

                    property int dayNumber:
                        index - new Date(root.year, root.month, 1).getDay() + 1

                    property bool validDay:
                        dayNumber > 0 &&
                        dayNumber <= new Date(root.year, root.month + 1, 0).getDate()

                    property bool isToday:
                        validDay &&
                        root.year === new Date().getFullYear() &&
                        root.month === new Date().getMonth() &&
                        dayNumber === new Date().getDate()

                    Rectangle {
                        anchors.centerIn: parent
                        width: 27
                        height: 27
                        radius: 9
                        color: parent.isToday ? root.cherry : "transparent"
                    }

                    Text {
                        anchors.centerIn: parent
                        text: parent.validDay ? parent.dayNumber : ""
                        color: parent.isToday ? "#ffffff" : root.textColor
                        opacity: parent.validDay ? 1 : 0
                        font.pixelSize: 11
                        font.bold: parent.isToday
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }

        Text {
            text: "✿  a little day at a time"
            color: root.muted
            font.pixelSize: 10
            Layout.alignment: Qt.AlignHCenter
        }
    }
}

