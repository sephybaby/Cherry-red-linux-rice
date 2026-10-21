import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// Shows one quote from an Obsidian note. One quote per line (bullets, "> " blockquotes and
// numbering are fine, headings and frontmatter are ignored). Click the bar for another quote.
Rectangle {
    id: bar

    property color cherry: "#8f142b"
    property color pink: "#a8324a"
    property color muted: "#a96b7b"
    property color textColor: "#ffe8ee"
    property color surface: "#42030f"
    property color borderColor: "#240309"
    property color hoverColor: "#58101d"

    property string filePath: "/home/sephy/Obsidian/Uni/System/Life Lessons & Quotes.md"
    property int changeEveryMinutes: 30

    property var quotes: []
    property string quote: ""
    property bool loaded: false

    radius: 14
    color: mouse.containsMouse ? hoverColor : surface
    border.color: borderColor

    // ------------------------------------------------------------------
    function parse(text) {
        var out = []
        var lines = text.replace(/\r/g, "").split("\n")
        var inFrontmatter = false
        var inFence = false
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim()
            if (i === 0 && l === "---") { inFrontmatter = true; continue }
            if (inFrontmatter) { if (l === "---") inFrontmatter = false; continue }
            if (l.indexOf("```") === 0) { inFence = !inFence; continue }   // skip code blocks
            if (inFence) continue
            if (l === "" || l === "---" || l.charAt(0) === "#")
                continue
            l = l.replace(/^(>\s*)+/, "")                 // blockquote
            l = l.replace(/^([-*+]|\d+[.)])\s+/, "")      // bullets / numbering
            l = l.replace(/^\[[ xX]\]\s*/, "")            // checkbox
            l = l.replace(/\*\*|__|==/g, "")              // bold / highlight markers
            l = l.replace(/\[\[([^\]|]+)\|?([^\]]*)\]\]/g, function (m, a, b) { return b || a })
            l = l.replace(/^[“"]+/, "")                          // we draw our own quote marks
            l = l.replace(/[”"]+(\s*[—–-]\s)/, "$1")               // "text" — Author  ->  text — Author
            l = l.replace(/[”"]+$/, "")
            l = l.trim()
            if (l.length >= 3)
                out.push(l)
        }
        return out
    }

    function pick() {
        if (quotes.length === 0) {
            quote = ""
            return
        }
        if (quotes.length === 1) {
            quote = quotes[0]
            return
        }
        var next = quote
        while (next === quote)
            next = quotes[Math.floor(Math.random() * quotes.length)]
        quote = next
    }

    function ingest(text) {
        quotes = parse(text)
        loaded = true
        // keep the current quote if it is still in the file, otherwise choose a new one
        if (quotes.indexOf(quote) < 0)
            pick()
    }

    FileView {
        id: file
        path: bar.filePath
        watchChanges: true
        printErrors: false
        onLoaded: bar.ingest(text())
        onFileChanged: reload()
        onLoadFailed: bar.ingest("")
    }

    // Re-check now and then (covers editors that replace the file) and rotate the quote.
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: file.reload()
    }
    Timer {
        interval: bar.changeEveryMinutes * 60000
        running: true
        repeat: true
        onTriggered: bar.pick()
    }

    // ------------------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 12

        Text {
            text: "“"
            color: bar.cherry
            font.pixelSize: 30
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: bar.quote !== ""
                  ? bar.quote
                  : (bar.loaded ? "Add quotes to “Life Lessons & Quotes.md”, one per line." : "")
            color: bar.quote !== "" ? bar.textColor : bar.muted
            font.pixelSize: 12
            font.italic: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        Text {
            text: "”"
            color: bar.cherry
            font.pixelSize: 30
            font.bold: true
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: bar.pick()
    }
}
