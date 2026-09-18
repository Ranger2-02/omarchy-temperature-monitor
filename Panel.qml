import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Temperature Monitor popup, opened by clicking the bar widget.
//
// Shows the live CPU and GPU readings, coloured by the same green/orange/red
// thresholds as the bar, and a switch for each that hides or shows it on the
// bar. The switches persist to the widget's shell.json entry, so they survive
// a restart and apply on every monitor. They exist for machines without a
// discrete GPU, where the GPU readout can be switched off entirely.
Panel {
  id: root
  moduleName: "ranger.tempmon"
  ipcTarget: "ranger.tempmon"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — TempMon.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Live readings mirror the bar widget, which owns the single sensor
  // sampler — no second temp poller here, so the popup can never disagree
  // with the bar it was opened from.
  readonly property real cpuTemp: hostWidget ? Number(hostWidget.cpuTemp) : NaN
  readonly property real dgpuTemp: hostWidget ? Number(hostWidget.dgpuTemp) : NaN
  readonly property real igpuTemp: hostWidget ? Number(hostWidget.igpuTemp) : NaN
  readonly property real gpuTemp: !isNaN(dgpuTemp) ? dgpuTemp : igpuTemp

  readonly property int warnTemp: Number(setting("warnTemp", 75))
  readonly property int hotTemp: Number(setting("hotTemp", 90))
  readonly property string unit: String(setting("unit", "Celsius"))
  readonly property bool showUnit: setting("showUnit", false) === true
  readonly property bool showCpu: setting("showCpu", true) !== false
  readonly property bool showGpu: setting("showGpu", true) !== false

  // Same palette as the bar readout, so a hot reading is the same red here
  // and on the bar.
  readonly property color colorNormal: "#8ec07c"
  readonly property color colorWarn: "#fe8019"
  readonly property color colorHot: "#fb4934"

  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentDimmed: Qt.darker(contentForeground, 1.5)
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Keyboard cursor: two rows, j/k walks between them, Enter flips the
  // focused one. Hover on a row moves the cursor to it, and the visuals
  // always come from CursorSurface (hasCursor), never from containsMouse.
  property bool cursorActive: false
  property string focusSection: "cpu"

  function convert(t) {
    return unit === "Fahrenheit" ? t * 9 / 5 + 32 : t
  }

  function reading(t) {
    var suffix = showUnit ? (unit === "Fahrenheit" ? "°F" : "°C") : "°"
    return isNaN(t) ? "--" + suffix : Math.round(convert(t)) + suffix
  }

  // The popup colours its readings by the same threshold rules as the bar;
  // a missing sensor ("--") just reads as inactive.
  function tempColor(t) {
    if (isNaN(t)) return contentDimmed
    if (t >= hotTemp) return colorHot
    if (t >= warnTemp) return colorWarn
    return colorNormal
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. The host
  // widget reads the same settings, so its bar readout updates in step.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setShowCpu(value) {
    var v = !!value
    if (v === root.showCpu) return
    persistSettings({ showCpu: v })
  }

  function setShowGpu(value) {
    var v = !!value
    if (v === root.showGpu) return
    persistSettings({ showGpu: v })
  }

  function moveCursor(delta) {
    if (!cursorActive) {
      cursorActive = true
      return
    }
    if (delta > 0) {
      if (root.focusSection === "gpu") return
      root.focusSection = "gpu"
    } else if (delta < 0) {
      if (root.focusSection === "cpu") return
      root.focusSection = "cpu"
    }
  }

  function activateCursor() {
    if (!cursorActive) return
    if (root.focusSection === "cpu") root.setShowCpu(!root.showCpu)
    else root.setShowGpu(!root.showGpu)
  }

  function open() {
    if (root.hostWidget && root.hostWidget.refresh) root.hostWidget.refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  onOpenedChanged: {
    if (root.opened) {
      root.cursorActive = false
      root.focusSection = "cpu"
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        PanelSectionHeader {
          text: "TEMPERATURES"
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily
        }

        SensorRow {
          width: parent.width
          kind: "cpu"
          label: "CPU"
          temp: root.cpuTemp
          enabled: root.showCpu
        }

        SensorRow {
          width: parent.width
          kind: "gpu"
          label: "GPU"
          temp: root.gpuTemp
          enabled: root.showGpu
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Toggling a sensor off hides it from the bar. Middle-click the bar widget to refresh the sensors now."
          color: root.contentDimmed
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  // One sensor row: label, colour-coded live reading, and the show/hide
  // switch. The whole row owns the click — clicking anywhere flips the
  // switch, which is presentation only, like every other platform Toggle.
  component SensorRow: CursorSurface {
    id: row
    required property string kind
    required property string label
    required property real temp
    required property bool enabled

    readonly property bool rowSelected: root.cursorActive && root.focusSection === kind

    hasCursor: row.rowSelected
    foreground: root.contentForeground
    fill: Style.hoverFillFor(root.contentForeground, Color.accent)
    implicitHeight: rowInner.implicitHeight + Style.spacing.xl

    // Dim a sensor the user has hidden from the bar, so the toggle's effect
    // is visible even before looking back at the bar.
    opacity: row.enabled ? 1.0 : 0.55

    Behavior on opacity { NumberAnimation { duration: 120 } }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = row.kind
      }
      onClicked: {
        if (row.kind === "cpu") root.setShowCpu(!root.showCpu)
        else root.setShowGpu(!root.showGpu)
      }
    }

    PanelToolTip {
      visible: rowMouse.containsMouse
      text: row.enabled ? "Hide from the bar" : "Show in the bar"
      fontFamily: root.contentFontFamily
    }

    Item {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      height: implicitHeight
      implicitHeight: Math.max(nameText.implicitHeight, valueText.implicitHeight, barSwitch.implicitHeight)

      Text {
        id: nameText
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(48)
        text: row.label
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        id: valueText
        textFormat: Text.PlainText
        anchors.left: nameText.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.reading(row.temp)
        color: root.tempColor(row.temp)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      ToggleSwitch {
        id: barSwitch
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        checked: row.enabled
        hasCursor: row.rowSelected
        foreground: root.contentForeground
        accent: Color.accent
        // The row owns the click; the switch is presentation only.
        interactive: false
      }
    }
  }
}