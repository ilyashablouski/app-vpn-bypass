#!/usr/bin/env bash
# Исключения из VPN (split tunneling) через маршруты: трафик к указанным
# доменам/IP/приложениям идёт в обход VPN-туннеля, через обычный шлюз.
# Работает на macOS и Linux. Нужен root (sudo).
#
#   sudo ./vpn-bypass.sh apply    # один раз добавить маршруты
#   sudo ./vpn-bypass.sh watch    # держать маршруты актуальными (рекомендуется)
#   sudo ./vpn-bypass.sh status   # показать добавленные маршруты
#   sudo ./vpn-bypass.sh clear    # удалить все добавленные маршруты

set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${BYPASS_CONFIG:-$DIR/bypass.conf}"
STATE="${BYPASS_STATE:-/tmp/vpn-bypass.routes}"
INTERVAL="${BYPASS_INTERVAL:-30}"
OS="$(uname -s)"

GATEWAY=""
IFACE=""

die() { echo "Ошибка: $*" >&2; exit 1; }
log() { echo "[$(date +%H:%M:%S)] $*"; }

need_root() { [ "$(id -u)" -eq 0 ] || die "запустите через sudo"; }

detect_gateway() {
  [ -n "${BYPASS_GATEWAY:-}" ] && { GATEWAY="$BYPASS_GATEWAY"; IFACE="${BYPASS_IFACE:-}"; return; }
  if [ "$OS" = "Darwin" ]; then
    # Берём default-маршрут физического интерфейса (enX), а не VPN (utunX).
    read -r GATEWAY IFACE < <(netstat -rn -f inet 2>/dev/null |
      awk '$1=="default" && $NF ~ /^en[0-9]+$/ && $2 ~ /^[0-9.]+$/ {print $2, $NF; exit}')
  else
    read -r GATEWAY IFACE < <(ip -4 route show default 2>/dev/null |
      awk '{for(i=1;i<=NF;i++){if($i=="via")g=$(i+1); if($i=="dev")d=$(i+1)}
            if(d !~ /^(tun|tap|wg|ppp|utun)/ && g!=""){print g, d; exit}}')
  fi
  [ -n "$GATEWAY" ] || die "не удалось определить обычный шлюз. Задайте BYPASS_GATEWAY=192.168.x.x (и BYPASS_IFACE=...)"
}

resolve() {
  local d="$1"
  if command -v dig >/dev/null; then
    dig +short +time=2 +tries=1 A "$d" 2>/dev/null
  elif [ "$OS" = "Darwin" ]; then
    dscacheutil -q host -a name "$d" 2>/dev/null | awk '/^ip_address:/{print $2}'
  else
    getent ahostsv4 "$d" 2>/dev/null | awk '{print $1}' | sort -u
  fi | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'
}

app_ips() {
  command -v lsof >/dev/null || return 0
  lsof -nP -a -c "$1" -iTCP -iUDP 2>/dev/null |
    grep -oE -- '->[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:' | tr -d '>:-' | sort -u
}

is_ip() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; }

add_route() {
  local target="$1" kind="-host"
  grep -qxF "$target" "$STATE" 2>/dev/null && return 0
  if [ "$OS" = "Darwin" ]; then
    [[ "$target" == */* ]] && kind="-net"
    route -n add $kind "$target" "$GATEWAY" >/dev/null 2>&1 || return 1
  else
    ip route replace "$target" via "$GATEWAY" ${IFACE:+dev "$IFACE"} 2>/dev/null || return 1
  fi
  echo "$target" >> "$STATE"
  log "в обход VPN: $target"
}

del_route() {
  local target="$1" kind="-host"
  if [ "$OS" = "Darwin" ]; then
    [[ "$target" == */* ]] && kind="-net"
    route -n delete $kind "$target" >/dev/null 2>&1
  else
    ip route del "$target" >/dev/null 2>&1
  fi
}

# Печатает записи конфига в виде "тип значение".
read_config() {
  [ -f "$CONFIG" ] || die "нет файла конфигурации: $CONFIG"
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [ -z "$line" ] && continue
    case "$line" in
      app:*) echo "app $(echo "${line#app:}" | xargs)" ;;
      *)     echo "host $line" ;;
    esac
  done < "$CONFIG"
}

apply() {
  detect_gateway
  touch "$STATE"
  local type value ip
  while read -r type value; do
    if [ "$type" = "app" ]; then
      for ip in $(app_ips "$value"); do add_route "$ip"; done
    elif is_ip "$value"; then
      add_route "$value"
    else
      value="${value#\*.}"
      local found=0
      for ip in $(resolve "$value"); do found=1; add_route "$ip"; done
      [ "$found" -eq 1 ] || log "не удалось получить IP для $value"
    fi
  done < <(read_config)
}

clear_routes() {
  [ -f "$STATE" ] || { log "нечего удалять"; return; }
  while read -r t; do del_route "$t"; done < "$STATE"
  rm -f "$STATE"
  log "все маршруты-исключения удалены"
}

case "${1:-}" in
  apply)  need_root; apply ;;
  watch)  need_root
          trap 'clear_routes; exit 0' INT TERM
          log "слежение запущено (интервал ${INTERVAL}с), Ctrl+C - остановить и очистить"
          while true; do apply; sleep "$INTERVAL" & wait $!; done ;;
  status) [ -f "$STATE" ] && cat "$STATE" || echo "маршрутов нет" ;;
  clear)  need_root; clear_routes ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
