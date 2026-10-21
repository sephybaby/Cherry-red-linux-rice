import QtQuick

// Arc seek slider that wraps around the top of the vinyl.
//
// 0:00 is on the left, just below the record's horizontal diameter; the arc
// rises over the top and comes down the right side, ending a little below the
// diameter at the end of the song. The knob shows where the song is; drag it
// (or click the arc) to change the timestamp.
//
//   value          0..1, how far through the song we are (set from outside)
//   moved(v)       emitted continuously while dragging (preview)
//   seekRequested  emitted once on release with the chosen fraction 0..1
Item {
    id: slider

    property real value: 0
    property real arcRadius: width * 0.46       // a ring just outside the vinyl disc
    property real startAngle: Math.PI - 0.35    // left, ~20 degrees below the diameter
    property real sweep: Math.PI + 0.95         // positive = clockwise over the top, ends ~35 degrees below the right side
    property real lineWidth: 5

    property color trackColor: "#24ffffff"
    property color fillColor: "#ff173f"
    property color handleColor: "#ffe8ee"
    property color labelColor: "#a47d8c"
    property string startText: "0:00"
    property string endText: "--:--"

    readonly property bool dragging: area.active
    // what the knob/fill show: the drag position while dragging, else value
    readonly property real shown: Math.max(0, Math.min(1, area.active ? area.dragValue : value))

    signal moved(real v)
    signal seekRequested(real v)

    // point on the arc for t in 0..1
    function pointAt(t) {
        var ang = startAngle + t * sweep
        return Qt.point(width / 2 + arcRadius * Math.cos(ang), height / 2 + arcRadius * Math.sin(ang))
    }

    onShownChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
    onFillColorChanged: canvas.requestPaint()
    onEnabledChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.lineWidth = slider.lineWidth

            function trace(t0, t1) {
                var steps = Math.max(2, Math.ceil((t1 - t0) * Math.abs(slider.sweep) * 180 / Math.PI / 4))
                ctx.beginPath()
                for (var i = 0; i <= steps; i++) {
                    var p = slider.pointAt(t0 + (t1 - t0) * i / steps)
                    if (i === 0) ctx.moveTo(p.x, p.y)
                    else ctx.lineTo(p.x, p.y)
                }
                ctx.stroke()
            }

            ctx.strokeStyle = slider.trackColor
            trace(0, 1)

            if (slider.shown > 0.001) {
                ctx.strokeStyle = slider.fillColor
                trace(0, slider.shown)
            }
        }
    }

    // "0:00" just under where the arc starts
    Text {
        text: slider.startText
        color: slider.labelColor
        font.pixelSize: 9
        font.bold: true
        x: slider.pointAt(0).x - width / 2
        y: slider.pointAt(0).y + 12
    }

    // end marker + total time just under where the arc ends
    Rectangle {
        width: 8
        height: 8
        radius: 4
        color: "transparent"
        border.width: 1
        border.color: slider.labelColor
        x: slider.pointAt(1).x - width / 2
        y: slider.pointAt(1).y - height / 2
    }
    Text {
        text: slider.endText
        color: slider.labelColor
        font.pixelSize: 9
        font.bold: true
        x: slider.pointAt(1).x - width / 2
        y: slider.pointAt(1).y + 12
    }

    // the knob
    Rectangle {
        id: knob
        width: 16
        height: 16
        radius: 8
        color: slider.handleColor
        border.width: 2
        border.color: slider.fillColor
        opacity: slider.enabled ? 1 : 0.4
        scale: area.active ? 1.25 : 1.0
        x: slider.pointAt(slider.shown).x - width / 2
        y: slider.pointAt(slider.shown).y - height / 2
        Behavior on scale { NumberAnimation { duration: 80 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: slider.enabled
        cursorShape: Qt.PointingHandCursor

        property bool active: false
        property real dragValue: 0

        // Closest point on the arc to (mx, my).
        function nearest(mx, my, around) {
            var n = 1000
            var lo = 0
            var hi = n
            if (around >= 0) {
                lo = Math.max(0, Math.floor((around - 0.3) * n))
                hi = Math.min(n, Math.ceil((around + 0.3) * n))
            }
            var best = lo
            var bestD = Infinity
            for (var i = lo; i <= hi; i++) {
                var p = slider.pointAt(i / n)
                var d = (p.x - mx) * (p.x - mx) + (p.y - my) * (p.y - my)
                if (d < bestD) { bestD = d; best = i }
            }
            if (around >= 0 && Math.sqrt(bestD) > 40)
                return nearest(mx, my, -1)
            return { t: best / n, d: Math.sqrt(bestD) }
        }

        onPressed: mouse => {
            var hit = nearest(mouse.x, mouse.y, -1)
            if (hit.d > 18) {            // clicked the artwork, not the arc
                mouse.accepted = false
                return
            }
            active = true
            dragValue = hit.t
            slider.moved(hit.t)
        }

        onPositionChanged: mouse => {
            if (!active) return
            dragValue = nearest(mouse.x, mouse.y, dragValue).t
            slider.moved(dragValue)
        }

        onReleased: {
            if (!active) return
            active = false
            slider.seekRequested(dragValue)
        }

        onCanceled: active = false
    }
}
