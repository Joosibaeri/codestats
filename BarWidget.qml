import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// CodeStats: icon-only bar button. Click toggles the popup
// panel (Panel.qml) with this month's tokens, cost, and per-model split.
// Data: codestats.py sums every installed coding agent's local data.
BarWidget {
  id: root
  moduleName: "joosibaeri.codestats"

  property var usage: ({})
  property string updatedAt: ""
  property bool refreshPending: false
  property string range: "month"

  readonly property string summary: usage && usage.display
    ? String(usage.display) : "codestats …"

  function refresh() {
    if (usageProc.running) {
      refreshPending = true
      return
    }
    refreshPending = false
    usageProc.running = true
  }

  function setRange(r) {
    if (range === r) return
    range = r
    refresh()
  }

  function openStats() {
    if (root.bar) root.bar.run("omarchy-launch-floating-terminal-with-presentation bash -c 'mammouth stats --days 31 --models 10; echo; read -n1 -s -r -p \"Press any key to close...\"'")
  }


  // ---- Popup wiring. The bar tracks this widget, not the nested panel,
  //      so open/close delegate into the loaded Panel.qml item.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Component.onCompleted: refresh()

  Process {
    id: usageProc
    command: ["python3", Quickshell.env("HOME") + "/.config/omarchy/plugins/joosibaeri.codestats/codestats.py", "--range", root.range]
    onRunningChanged: {
      if (running) {
        stallTimer.restart()
        return
      }
      stallTimer.stop()
      if (root.refreshPending) root.refresh()
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var data
        try {
          data = JSON.parse(text || "{}")
        } catch (e) {
          console.warn("joosibaeri.codestats: bad JSON from helper:", text)
          return
        }
        root.usage = data
        root.updatedAt = Qt.formatTime(new Date(), "HH:mm:ss")
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "") console.warn("joosibaeri.codestats:", text.trim())
      }
    }
  }

  // A query that never returns would freeze the label until shell restart.
  Timer {
    id: stallTimer
    interval: 10000
    onTriggered: {
      usageProc.running = false
      root.refresh()
    }
  }

  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "joosibaeri.codestats"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // Icon-only bar button (drawn mini bar chart: no font dependency,
  // theme-aware via the bar foreground). Click toggles the popup panel.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: root.summary
    iconComponent: Component {
      Item {
        width: 15
        height: 13
        anchors.centerIn: parent

        Rectangle {
          x: 0; y: 8; width: 3; height: 5; radius: 1
          color: root.bar.foreground
        }
        Rectangle {
          x: 4; y: 5; width: 3; height: 8; radius: 1
          color: root.bar.foreground
        }
        Rectangle {
          x: 8; y: 2; width: 3; height: 11; radius: 1
          color: root.bar.foreground
        }
        Rectangle {
          x: 12; y: 6; width: 3; height: 7; radius: 1
          color: root.bar.foreground
          opacity: 0.55
        }
      }
    }
    onPressed: function(b) {
      // Left or right click toggles the usage popup; middle click opens the terminal stats.
      if (b === Qt.MiddleButton) {
        root.openStats()
      } else {
        root.togglePanel()
      }
    }
  }
}
