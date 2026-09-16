import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// CPU and GPU temperatures for the bar, colour-coded by threshold:
// green under the warn line, orange up to the hot line, red beyond it.
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
  readonly property int interval: Math.max(1000, Number(setting("interval", 3000)))

  readonly property color colorNormal: "#8ec07c"
  readonly property color colorWarn: "#fe8019"
  readonly property color colorHot: "#fb4934"

  readonly property color labelColor: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Prefer the discrete GPU, fall back to the integrated one when the dGPU is
  // absent or unreadable.
  readonly property real gpuTemp: !isNaN(dgpuTemp) ? dgpuTemp : igpuTemp

  readonly property string cpuText: (showLabel ? "CPU " : "") + reading(cpuTemp)
  readonly property string gpuText: (showLabel ? "GPU " : "") + reading(gpuTemp)

  function reading(t) {
    return isNaN(t) ? "--°" : Math.round(t) + "°"
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

  visible: showCpu || showGpu
  implicitWidth: Math.max(Style.space(12), readout.implicitWidth + Style.space(16))
  implicitHeight: root.vertical
    ? readout.implicitHeight + Style.space(12)
    : (root.bar ? root.bar.barSize : Style.bar.sizeHorizontal)

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
}
