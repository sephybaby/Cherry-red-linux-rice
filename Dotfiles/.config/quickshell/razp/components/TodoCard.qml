import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// To-do card backed by an Obsidian note.
//
// Reads and writes plain Markdown tasks ("- [ ] thing" / "- [x] thing") in one
// note, so Obsidian and the dashboard always show the same list. Everything in
// the note that isn't a task (headings, text, blank lines) is left untouched.
Rectangle {
    id: card

    property color cherry: "#8f142b"
    property color pink: "#a8324a"
    property color muted: "#a96b7b"
    property color textColor: "#ffe8ee"
    property color surface: "#42030f"
    property color surfaceLight: "#6e0c1c"
    property color borderColor: "#240309"
    property color hoverColor: "#58101d"

    // One note per day in this folder, named like 17-10-26.md (DD-MM-YY).
    // It is created when you add the first task of the day.
    property string folder: "/home/sephy/Obsidian/Uni/System/To-Dos"
    property string today: Qt.formatDate(new Date(), "dd-MM-yy")
    readonly property string fileName: today + ".md"
    readonly property string filePath: folder + "/" + fileName

    property var doc: []            // every line of the note, tasks and other text
    property string lastText: ""    // what the note looked like when we last read/wrote it
    property bool loaded: false
    property bool canSave: false    // never write until we know what is in the file
    property bool editing: false    // true while you type: don't reload under your fingers
    property int remaining: 0
    property string problem: ""

    implicitWidth: 300
    implicitHeight: 220
    radius: 16
    color: surface
    border.color: borderColor

    // A new day (or a changed folder) means a different note: start clean and load it.
    onFilePathChanged: {
        saveTimer.stop()
        loaded = false
        canSave = false
        lastText = ""
        doc = []
        problem = ""
        todoModel.clear()
        remaining = 0
        Qt.callLater(function () { file.reload() })
    }

    // ------------------------------------------------------------------
    // Markdown <-> list
    // ------------------------------------------------------------------
    function parse(text) {
        var out = []
        var lines = text.replace(/\r/g, "").split("\n")
        if (lines.length > 0 && lines[lines.length - 1] === "")
            lines.pop()
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^(\s*)[-*+] \[([ xX])\] ?(.*)$/)
            if (m)
                out.push({ task: true, indent: m[1], done: m[2] !== " ", text: m[3], raw: "" })
            else
                out.push({ task: false, raw: lines[i] })
        }
        return out
    }

    function serialize() {
        var lines = []
        for (var i = 0; i < doc.length; i++) {
            var e = doc[i]
            lines.push(e.task ? e.indent + "- [" + (e.done ? "x" : " ") + "] " + e.text : e.raw)
        }
        return lines.join("\n") + "\n"
    }

    function rebuild() {
        todoModel.clear()
        var left = 0
        for (var i = 0; i < doc.length; i++) {
            if (!doc[i].task)
                continue
            if (!doc[i].done)
                left++
            todoModel.append({ docIndex: i, done: doc[i].done, label: doc[i].text })
        }
        remaining = left
    }

    function ingest(text) {
        if (loaded && text === lastText)
            return
        loaded = true
        canSave = true
        lastText = text
        doc = parse(text)
        problem = ""
        rebuild()
    }

    function save() {
        if (!canSave) {
            problem = "Not saved: couldn't read the note first."
            return
        }
        var t = serialize()
        lastText = t
        file.setText(t)
    }

    // ------------------------------------------------------------------
    // Actions (called from the rows)
    // ------------------------------------------------------------------
    function toggle(row) {
        var e = doc[todoModel.get(row).docIndex]
        e.done = !e.done
        todoModel.setProperty(row, "done", e.done)
        remaining += e.done ? -1 : 1
        save()
    }

    function edit(row, newText) {
        doc[todoModel.get(row).docIndex].text = newText
        editing = true
        idleTimer.restart()
        saveTimer.restart()
    }

    function flush() {
        if (saveTimer.running) {
            saveTimer.stop()
            save()
        }
    }

    function remove(row) {
        doc.splice(todoModel.get(row).docIndex, 1)
        rebuild()
        save()
    }

    function add(text) {
        text = text.trim()
        if (text === "")
            return
        if (doc.length === 0) {
            doc.push({ task: false, raw: "# To-Dos " + today })
            doc.push({ task: false, raw: "" })
        }
        var last = -1
        for (var i = 0; i < doc.length; i++)
            if (doc[i].task) last = i
        var entry = { task: true, indent: "", done: false, text: text, raw: "" }
        if (last >= 0) doc.splice(last + 1, 0, entry)
        else doc.push(entry)
        rebuild()
        save()
        Qt.callLater(function () { list.positionViewAtEnd() })
    }

    // ------------------------------------------------------------------
    // The note on disk
    // ------------------------------------------------------------------
    ListModel { id: todoModel }

    FileView {
        id: file
        path: card.filePath
        watchChanges: true
        atomicWrites: false
        printErrors: false
        onLoaded: card.ingest(text())
        onFileChanged: if (!card.editing) reload()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                card.ingest("")     // note doesn't exist yet: it is created on the first task
            else
                card.problem = "Can't read the note (" + error + ")."
        }
        onSaveFailed: error => card.problem = "Couldn't save the note (" + error + ")."
        onSaved: card.problem = ""
    }

    // Make sure the folder exists so the first save can create the note.
    Process { command: ["mkdir", "-p", card.folder]; running: true }

    // Safety net in case a file-change event is missed (e.g. Obsidian replaced the file).
    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: if (!card.editing) file.reload()
    }
    // Roll over to the new day's note after midnight.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            var d = Qt.formatDate(new Date(), "dd-MM-yy")
            if (d !== card.today) {
                card.flush()
                card.today = d
            }
        }
    }
    Timer { id: saveTimer; interval: 500; onTriggered: card.save() }
    Timer { id: idleTimer; interval: 1500; onTriggered: card.editing = false }

    Process {
        id: openNote
        command: ["sh", "-c", "xdg-open \"obsidian://open?path=" + encodeURIComponent(card.filePath) + "\""]
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text { text: "TO-DO · " + card.today; color: card.muted; font.pixelSize: 9; font.letterSpacing: 1 }
            Text {
                text: card.remaining + (card.remaining === 1 ? " task left" : " tasks left")
                color: card.pink
                font.pixelSize: 9
            }
            Item { Layout.fillWidth: true }
            Text {
                text: "Open in Obsidian ↗"
                color: openMouse.containsMouse ? card.textColor : card.muted
                font.pixelSize: 9
                MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        openNote.running = false
                        openNote.running = true
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: card.problem !== ""
            text: card.problem
            color: "#ff8da4"
            font.pixelSize: 10
            wrapMode: Text.WordWrap
        }

        Text {
            Layout.fillWidth: true
            visible: card.loaded && todoModel.count === 0
            text: "Nothing to do. Add a task below."
            color: card.muted
            font.pixelSize: 11
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: todoModel
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row
                required property int index
                required property bool done
                required property string label
                required property int docIndex

                width: ListView.view.width
                height: 34
                radius: 10
                color: rowHover.hovered ? card.hoverColor : "transparent"

                HoverHandler { id: rowHover }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10

                    // Round checkbox
                    Rectangle {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        Layout.alignment: Qt.AlignVCenter
                        radius: 10
                        color: row.done ? card.cherry : "transparent"
                        border.width: 2
                        border.color: row.done ? card.cherry : (circleMouse.containsMouse ? card.pink : card.muted)

                        Text {
                            anchors.centerIn: parent
                            visible: row.done
                            text: "✓"
                            color: card.textColor
                            font.pixelSize: 12
                            font.bold: true
                        }

                        MouseArea {
                            id: circleMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.toggle(row.index)
                        }
                    }

                    // Click to edit the task in place
                    TextInput {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: row.label
                        color: row.done ? card.muted : card.textColor
                        font.pixelSize: 13
                        font.strikeout: row.done
                        selectByMouse: true
                        selectionColor: card.cherry
                        clip: true
                        onTextEdited: card.edit(row.index, text)
                        onEditingFinished: card.flush()
                    }

                    Text {
                        visible: rowHover.hovered
                        text: "✕"
                        color: deleteMouse.containsMouse ? card.pink : card.muted
                        font.pixelSize: 12
                        MouseArea {
                            id: deleteMouse
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var i = row.index
                                Qt.callLater(function () { card.remove(i) })
                            }
                        }
                    }
                }
            }
        }

        // Add a new task
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 12
            color: card.borderColor
            border.width: 1
            border.color: addInput.activeFocus ? card.cherry : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                    radius: 10
                    color: "transparent"
                    border.width: 2
                    border.color: card.muted
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: card.muted
                        font.pixelSize: 14
                    }
                }

                TextInput {
                    id: addInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    color: card.textColor
                    font.pixelSize: 13
                    selectByMouse: true
                    selectionColor: card.cherry
                    clip: true
                    onAccepted: {
                        card.add(text)
                        text = ""
                    }

                    Text {
                        visible: addInput.text.length === 0
                        text: "Add a task and press Enter"
                        color: card.muted
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
