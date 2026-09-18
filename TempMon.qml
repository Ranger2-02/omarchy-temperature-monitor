import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// CPU and GPU temperatures for the bar, colour-coded by threshold:
// green under the warn line, orange up to the hot line, red beyond it.
//
// Left-click opens a popup showing both readings in the same colours and
// toggling whether each appears on the bar — handy on machines without a
// discrete GPU, where the "GPU" readout can be hidden entirely. Middle-click
// re-samples the sensors immediately.
BarWidget {
  id: root
  moduleName: "ranger.tempmon"

  property real cpuTemp: NaN
  property real dgpuTemp: NaN
  property real igpuTemp: NaN

  readonly property int warnTemp: Number(setting("warnTemp", 75))
  readonly property int hotTemp: Number(setting("hotTemp", 90))
  readonly property bool showCpu: setting("showCpu", true) !== false
  readonly property bool showGpu: setting("showGpu", true) !== false
  readonly property bool showLabel: setting("showLabel", true) !== false
  readonly property string unit: String(setting("unit", "Celsius"))
  readonly property bool showUnit: setting("showUnit", false) === true
  readonly property int interval: Math.max(1000, Number(setting("interval", 3000)))

  readonly property color colorNormal: "#8ec07c"
  readonly property color colorWarn: "#fe8019"
  readonly property color colorHot: "#fb4934"

  readonly property color labelColor: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The bar's tooltip coordinator only displays for targets whose
  // tooltipHovered is true (WidgetButton exposes the same). Back it with the
  // click surface's hover state so the "Temperature Monitor" name follows the
  // cursor over the readout.
  readonly property bool tooltipHovered: visible && clickArea.containsMouse

  // Prefer the discrete GPU, fall back to the integrated one when the dGPU is
  // absent or unreadable.
  readonly property real gpuTemp: !isNaN(dgpuTemp) ? dgpuTemp : igpuTemp

  readonly property string cpuText: (showLabel ? "CPU " : "") + reading(cpuTemp)
  readonly property string gpuText: (showLabel ? "GPU " : "") + reading(gpuTemp)

  // Thresholds are always in Celsius (they describe the hardware); only the
  // displayed value follows the chosen unit.
  function convert(t) {
    return unit === "Fahrenheit" ? t * 9 / 5 + 32 : t
  }

  function reading(t) {
    var suffix = showUnit ? (unit === "Fahrenheit" ? "°F" : "°C") : "°"
    return isNaN(t) ? "--" + suffix : Math.round(convert(t)) + suffix
  }

  function tempColor(t) {
    if (isNaN(t)) return labelColor
    if (t >= hotTemp) return colorHot
    if (t >= warnTemp) return colorWarn
    return colorNormal
  }

  function refresh() {
    if (!sampler.running) sampler.running = true
  }

  function consume(line) {
    var parts = String(line || "").trim().split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].split("=")
      if (kv.length !== 2) continue
      var value = kv[1] === "" ? NaN : Number(kv[1])
      if (kv[0] === "cpu") root.cpuTemp = value
      else if (kv[0] === "dgpu") root.dgpuTemp = value
      else if (kv[0] === "igpu") root.igpuTemp = value
    }
  }

  // ---- Popup. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
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

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: {
    injectPanel()
    syncClickRegistration()
  }
  onSettingsChanged: injectPanel()

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
    target: "ranger.tempmon"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  // The bar's popout coordinator hands clicks on an open panel's overlay to
  // registered click targets, so clicking this widget while another popup is
  // open switches popups instead of dismissing. WidgetButton registers
  // itself; a custom multi-colour readout has to do it manually.
  property var registeredBar: null

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(clickArea)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(clickArea)
  }

  Component.onDestruction: {
    if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(clickArea)
  }

  visible: showCpu || showGpu
  implicitWidth: Math.max(Style.space(12), readout.implicitWidth + Style.space(16))
  implicitHeight: root.vertical
    ? readout.implicitHeight + Style.space(12)
    : (root.bar ? root.bar.barSize : Style.bar.sizeHorizontal)

  // The panel is anchored to the widget, so the bar's open-panel dot under it
  // should match the text label rather than the whole slot.
  readonly property real openPanelIndicatorWidth: readout.implicitWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  Process {
    id: sampler
    command: ["bash", String(Qt.resolvedUrl("temps.sh")).replace("file://", "")]
    stdout: SplitParser {
      onRead: function(line) { root.consume(line) }
    }
  }

  Timer {
    interval: root.interval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Grid {
    id: readout
    anchors.centerIn: parent
    columns: root.vertical ? 1 : 2
    rowSpacing: Style.space(4)
    columnSpacing: Style.space(8)

    Text {
      visible: root.showCpu
      text: root.cpuText
      color: root.tempColor(root.cpuTemp)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
    }

    Text {
      visible: root.showGpu
      text: root.gpuText
      color: root.tempColor(root.gpuTemp)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      textFormat: Text.PlainText
      renderType: Text.NativeRendering
    }
  }

  // Click surface on top of the readout: hover shows the widget's name,
  // left/right toggles the popup, middle re-samples the sensors.
  MouseArea {
    id: clickArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: {
      if (root.bar && root.bar.showTooltip) root.bar.showTooltip(root, "Temperature Monitor")
    }

    onExited: {
      if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(root)
    }

    // Bar click-target contract: the popout coordinator calls triggerPress
    // on registered targets in place of a real pointer event.
    function triggerPress(button) {
      if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(root)
      if (button === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    onClicked: function(mouse) {
      if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(root)
      if (mouse.button === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}