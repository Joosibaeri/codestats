import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// CodeStats popup in the network-panel style:
// hero, stat grid, per-model section, bordered action buttons.
// BarWidget.qml owns the bar button and hands this panel the button
// to anchor against (plus itself as hostWidget for data + actions).
Panel {
  id: root
  moduleName: "joosibaeri.codestats"
  ipcTarget: "joosibaeri.codestats"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget (popout coordination compares against `slot.activeItem`).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property var usage: hostWidget ? hostWidget.usage : ({})
  readonly property string updatedAt: hostWidget ? hostWidget.updatedAt : ""
  readonly property string monthLabel: usage && usage.label
    ? String(usage.label).toUpperCase() : ""

  function refresh() {
    if (hostWidget) hostWidget.refresh()
  }

  function openStats() {
    if (hostWidget) hostWidget.openStats()
    root.close()
  }


  function open() {
    root.controller.show()
    root.refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function fmtNum(n) {
    // Manual thousands grouping: the QML engine's toLocaleString() flips
    // to exponential notation past ~1M ("1.22586e+06").
    var s = String(Math.round(Number(n || 0)));
    if (s.indexOf("e") !== -1 || s.indexOf("E") !== -1) {
      s = Number(n || 0).toFixed(0);
    }
    var neg = "";
    if (s.charAt(0) === "-") {
      neg = "-";
      s = s.slice(1);
    }
    var out = "";
    while (s.length > 3) {
      out = "," + s.slice(-3) + out;
      s = s.slice(0, -3);
    }
    return neg + s + out;
  }

  function fmtShort(n) {
    n = Number(n || 0)
    if (n >= 1000000) {
      var m = n / 1000000
      return (m < 100 ? m.toFixed(1) : Math.round(m)) + "M"
    }
    if (n >= 1000) {
      var k = n / 1000
      return (k < 100 ? k.toFixed(1) : Math.round(k)) + "K"
    }
    return String(Math.round(n))
  }

  function fmtMoney(v) {
    return "$" + Number(v || 0).toFixed(2)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
      }
    }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      // ---------- Hero: icon · CodeStats + range · refresh ----------
      Item {
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroRefresh.implicitHeight)

        Item {
          id: heroIcon
          width: 26
          height: 22
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter

          Rectangle {
            x: 0; y: 14; width: 5; height: 8; radius: 1.5
            color: root.bar.foreground
          }
          Rectangle {
            x: 7; y: 9; width: 5; height: 13; radius: 1.5
            color: root.bar.foreground
          }
          Rectangle {
            x: 14; y: 4; width: 5; height: 18; radius: 1.5
            color: root.bar.foreground
          }
          Rectangle {
            x: 21; y: 11; width: 5; height: 11; radius: 1.5
            color: root.bar.foreground
            opacity: 0.55
          }
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: heroRefresh.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "CodeStats"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: text !== ""
            text: root.monthLabel
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
          }
        }

        Button {
          id: heroRefresh
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""
          tooltipText: "Refresh now"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          iconSize: Style.font.subtitle * 1.5
          horizontalPadding: Style.space(5)
          verticalPadding: Style.space(2)
          onClicked: root.refresh()
        }
      }

      // ---------- Time range ----------
      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: [
            { id: "7d", label: "7d" },
            { id: "30d", label: "30d" },
            { id: "month", label: "Month" },
            { id: "last-month", label: "Last mo" },
            { id: "year", label: "Year" },
            { id: "last-year", label: "Last yr" },
            { id: "all", label: "All" }
          ]

          delegate: Button {
            required property var modelData
            text: modelData.label
            selected: root.hostWidget && root.hostWidget.range === modelData.id
            fontSize: Style.font.caption
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(3)
            bordered: true
            onClicked: if (root.hostWidget) root.hostWidget.setRange(modelData.id)
          }
        }
      }

      // ---------- Stat grid: label left, value right ----------
      GridLayout {
        width: parent.width
        columns: 4
        columnSpacing: Style.space(20)
        rowSpacing: Style.spacing.labelGap

        InfoLabel { text: "Fresh" }
        DetailValue { text: root.fmtShort(root.usage.fresh) }
        InfoLabel { text: "Cost" }
        DetailValue { text: root.fmtMoney(root.usage.cost) }

        InfoLabel { text: "Sessions" }
        DetailValue { text: root.fmtNum(root.usage.sessions) }
        InfoLabel { text: "Prompts" }
        DetailValue { text: root.fmtNum(root.usage.prompts) }

        InfoLabel { text: "Input" }
        DetailValue { text: root.fmtNum(root.usage.input) }
        InfoLabel { text: "Output" }
        DetailValue { text: root.fmtNum(root.usage.output) }

        InfoLabel { text: "Reasoning" }
        DetailValue { text: root.fmtNum(root.usage.reasoning) }
        InfoLabel { text: "Cache re-read" }
        DetailValue { text: root.fmtNum(root.usage.cache) }
      }

      // ---------- Tokens by agent ----------
      PanelSeparator {
        foreground: root.bar.foreground
      }

      Column {
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "BY AGENT"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          Repeater {
            model: root.usage.agents || []

            delegate: Item {
              required property var modelData
              width: parent.width
              implicitHeight: Math.max(agentName.implicitHeight, agentValue.implicitHeight)

              Text {
                id: agentName
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: agentValue.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: String(modelData.name || "?")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: agentValue
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtShort(modelData.fresh) + " · " + root.fmtMoney(modelData.cost)
                color: root.bar.foreground
                opacity: 0.75
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Text {
            visible: !(root.usage.agents && root.usage.agents.length)
            textFormat: Text.PlainText
            width: parent.width
            text: "No agent data yet."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // ---------- Tokens by model ----------
      PanelSeparator {
        foreground: root.bar.foreground
      }

      Column {
        width: parent.width
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "TOKENS BY MODEL"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          Repeater {
            model: root.usage.models || []

            delegate: Item {
              required property var modelData
              width: parent.width
              implicitHeight: Math.max(modelName.implicitHeight, modelValue.implicitHeight)

              Text {
                id: modelName
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: modelValue.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                text: String(modelData.name || "?")
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                id: modelValue
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtShort(modelData.fresh) + " · " + root.fmtNum(modelData.prompts) + " prompts"
                color: root.bar.foreground
                opacity: 0.75
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Text {
            visible: !(root.usage.models && root.usage.models.length)
            textFormat: Text.PlainText
            width: parent.width
            text: "No usage this month yet."
            color: root.bar.foreground
            opacity: 0.6
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }

      // ---------- Actions ----------
      PanelSeparator {
        foreground: root.bar.foreground
      }

      Button {
        id: refreshButton
        width: parent.width
        text: "Refresh"
        tooltipText: "Re-read usage now (R)"
        fontSize: Style.font.bodySmall
        foreground: root.bar.foreground
        fontFamily: root.bar.fontFamily
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
        bordered: true
        onClicked: root.refresh()
      }

      Text {
        visible: root.updatedAt !== ""
        textFormat: Text.PlainText
        width: parent.width
        horizontalAlignment: Text.AlignRight
        text: "Updated " + root.updatedAt
        color: root.bar.foreground
        opacity: 0.45
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component DetailValue: InfoValue {
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight
  }
}
