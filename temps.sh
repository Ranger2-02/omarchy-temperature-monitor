#!/usr/bin/env bash
# Thermal snapshot for the ranger.tempmon bar widget.
# Emits: cpu=<degC> dgpu=<degC> igpu=<degC>
# A field is left empty when that sensor is not present on this machine.

read_mdeg() {
  [ -r "$1" ] || return 0
  local v
  v=$(cat "$1" 2>/dev/null) || return 0
  case "$v" in
    ''|*[!0-9]*) return 0 ;;
  esac
  echo $((v / 1000))
}

cpu=""
for zone in /sys/class/thermal/thermal_zone*; do
  [ "$(cat "$zone/type" 2>/dev/null)" = "x86_pkg_temp" ] || continue
  cpu=$(read_mdeg "$zone/temp")
  break
done

# No package sensor: fall back to the hottest thermal zone.
if [ -z "$cpu" ]; then
  for zone in /sys/class/thermal/thermal_zone*; do
    t=$(read_mdeg "$zone/temp")
    [ -z "$t" ] && continue
    [ -z "$cpu" ] || [ "$t" -gt "$cpu" ] && cpu=$t
  done
fi

dgpu=""
igpu=""
for h in /sys/class/drm/card*/device/hwmon/hwmon*; do
  [ -d "$h" ] || continue
  case "$(cat "$h/name" 2>/dev/null)" in
    amdgpu) [ -z "$dgpu" ] && dgpu=$(read_mdeg "$h/temp1_input") ;;
    i915)   [ -z "$igpu" ] && igpu=$(read_mdeg "$h/temp1_input") ;;
  esac
done

printf 'cpu=%s dgpu=%s igpu=%s\n' "$cpu" "$dgpu" "$igpu"
