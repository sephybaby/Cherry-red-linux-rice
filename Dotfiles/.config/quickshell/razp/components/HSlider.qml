import QtQuick

// Horizontal slider: value is 0..100, emits moved(v) while you click/drag.
Item {
    id: slider

    property real value: 0
    property color trackColor: "#240309"
    property color fillColor: "#8f142b"
    property color handleColor: "#ffe8ee"
    readonly property bool dragging: area.pressed

    signal moved(int v)

    implicitHeight: 24

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 7
        radius: 4
        color: slider.trackColor

        Rectangle {
            width: handle.x + handle.width / 2
            height: parent.height
            radius: 4
            color: slider.fillColor
        }
    }

    Rectangle {
        id: handle
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        color: slider.handleColor
        scale: area.pressed ? 1.2 : 1.0
        x: (slider.width - width) * Math.max(0, Math.min(100, slider.value)) / 100
        Behavior on scale { NumberAnimation { duration: 80 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        function pick(mx) {
            var ratio = (mx - handle.width / 2) / (slider.width - handle.width)
            slider.moved(Math.round(Math.max(0, Math.min(1, ratio)) * 100))
        }

        onPressed: mouse => pick(mouse.x)
        onPositionChanged: mouse => { if (pressed) pick(mouse.x) }
    }
}
