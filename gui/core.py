"""Логика приложения без GUI: конфиг, статус VPN, запуск/остановка скрипта."""
import os
import plistlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "vpn-bypass.sh"
CONFIG = ROOT / "bypass.conf"
PID_FILE = Path("/tmp/vpn-bypass.pid")
LOG_FILE = Path("/tmp/vpn-bypass.log")

HEADER = "# Файл управляется приложением VPN Bypass. Формат: домен / IP / app:Имя\n"


def load_entries(path=CONFIG):
    entries = []
    if not Path(path).exists():
        return entries
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("app:"):
            entries.append(("app", line[4:].strip()))
        else:
            entries.append(("host", line))
    return entries


def save_entries(entries, path=CONFIG):
    lines = [HEADER]
    for kind, value in entries:
        lines.append(f"app:{value}\n" if kind == "app" else f"{value}\n")
    Path(path).write_text("".join(lines), encoding="utf-8")


def normalize_host(text):
    text = text.strip().lower()
    text = re.sub(r"^[a-z]+://", "", text)
    text = text.split("/", 1)[0] if not re.match(r"^[\d.]+/\d+$", text) else text
    return text.strip()


def valid_host(text):
    if re.match(r"^\d{1,3}(\.\d{1,3}){3}(/\d{1,2})?$", text):
        return True
    return bool(re.match(r"^(\*\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$", text))


def add_entry(entries, kind, value):
    value = value.strip()
    if not value or (kind, value) in entries:
        return False
    entries.append((kind, value))
    return True


def app_process_name(app_path):
    """Имя исполняемого файла из .app (то, что видно в lsof/ps)."""
    app_path = Path(app_path)
    try:
        with open(app_path / "Contents" / "Info.plist", "rb") as f:
            name = plistlib.load(f).get("CFBundleExecutable")
        if name:
            return name
    except (OSError, plistlib.InvalidFileException):
        pass
    return app_path.stem


def parse_vpn_active(netstat_output):
    """VPN активен, если default-маршрут (или 0/1, 128.0/1) идёт через utun*."""
    for line in netstat_output.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[0] in ("default", "0/1", "128.0/1"):
            if parts[-1].startswith("utun") or parts[3].startswith("utun"):
                return True
    return False


def is_vpn_connected():
    try:
        out = subprocess.run(["netstat", "-rn", "-f", "inet"], capture_output=True,
                             text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return parse_vpn_active(out)


def is_vpn_app_running():
    r = subprocess.run(["pgrep", "-fi", "urban ?vpn"], capture_output=True)
    return r.returncode == 0


def running_pid():
    try:
        pid = int(PID_FILE.read_text().strip())
    except (OSError, ValueError):
        return None
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return None
    except PermissionError:
        pass
    return pid


def _admin(shell_cmd):
    escaped = shell_cmd.replace("\\", "\\\\").replace('"', '\\"')
    script = f'do shell script "{escaped}" with administrator privileges'
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return r.returncode == 0, r.stderr.strip()


def start_script():
    if running_pid():
        return True, ""
    q = lambda p: "'" + str(p).replace("'", "'\\''") + "'"
    cmd = (f"BYPASS_CONFIG={q(CONFIG)} nohup {q(SCRIPT)} watch >> {q(LOG_FILE)} 2>&1 "
           f"& echo $! > {q(PID_FILE)}")
    return _admin(cmd)


def stop_script():
    pid = running_pid()
    if not pid:
        return True, ""
    return _admin(f"kill {pid}; sleep 1; rm -f {PID_FILE}")
