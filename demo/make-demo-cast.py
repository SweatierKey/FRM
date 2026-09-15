#!/usr/bin/env python3
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FRM = ROOT / "frm"
CAST = ROOT / "demo" / "frm-demo.cast"


def write(path: pathlib.Path, text: str, executable: bool = False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


def setup_fixture(base: pathlib.Path):
    admin = base / "admin"
    state = base / "state"
    mockbin = base / "bin"
    admin.mkdir()
    state.mkdir()
    mockbin.mkdir()

    # 11g / OPMN instance.
    legacy = admin / "ohs_legacy_11119"
    (legacy / "bin").mkdir(parents=True)
    (state / "ohs_legacy_11119").write_text("running\n")
    write(
        legacy / "bin" / "opmnctl",
        r'''#!/usr/bin/env bash
set -u
state_file="$FRM_DEMO_STATE_DIR/ohs_legacy_11119"
action="${1:-status}"
case "$action" in
  status)
    echo
    echo "Processes in Instance: ohs_legacy_11119"
    if [[ "${2:-}" == "-l" ]]; then
      echo "ias-component | process-type | pid | status | uid | memused | uptime | ports"
      if grep -q running "$state_file"; then
        echo "ohs1 | OHS | 4101 | Alive | 1 | 2 | 3 | https:8443,http:7777"
      else
        echo "ohs1 | OHS | N/A | Down | 1 | 0 | 0 | https:8443,http:7777"
      fi
    else
      echo "---------------------------------+--------------------+---------+---------"
      echo "ias-component                    | process-type       |     pid | status"
      echo "---------------------------------+--------------------+---------+---------"
      if grep -q running "$state_file"; then
        echo "ohs1                             | OHS                |    4101 | Alive"
      else
        echo "ohs1                             | OHS                |     N/A | Down"
      fi
    fi
    ;;
  start)
    echo running > "$state_file"
    echo "opmnctl start: opmn and managed processes started"
    ;;
  stop)
    echo down > "$state_file"
    echo "opmnctl stop: opmn and managed processes stopped"
    ;;
  *)
    echo "unsupported mock action: $action" >&2
    exit 1
    ;;
esac
''',
        True,
    )

    # 12c instances.
    for name, initial in [("ohs_portal", "running"), ("ohs_api", "down")]:
        inst = admin / name
        (inst / "bin").mkdir(parents=True)
        (inst / "config" / "fmwconfig" / "components" / "OHS" / "instances" / name).mkdir(parents=True)
        (inst / "bin" / "startNodeManager.sh").write_text("#!/usr/bin/env bash\n")
        listen = "8080" if name == "ohs_portal" else "8090"
        (inst / "config" / "fmwconfig" / "components" / "OHS" / "instances" / name / "httpd.conf").write_text(f"Listen {listen}\n")
        (state / name).write_text(initial + "\n")

    write(
        mockbin / "systemctl",
        r'''#!/usr/bin/env bash
set -u
cmd="${1:-}"
shift || true
case "$cmd" in
  show)
    unit="${@: -1}"
    case "$unit" in
      ohs_portal.service|ohs_api.service) echo "LoadState=loaded" ;;
      *) echo "LoadState=not-found"; exit 4 ;;
    esac
    ;;
  status)
    unit="${1:-}"
    name="${unit%.service}"
    state_file="$FRM_DEMO_STATE_DIR/$name"
    echo "● $unit - SYSV: Oracle HTTP Server"
    echo "     Loaded: loaded (/etc/rc.d/init.d/$name; generated)"
    if grep -q running "$state_file"; then
      echo "     Active: active (exited) since Tue 2026-09-15 20:00:00 CEST; 2h ago"
      echo "       Docs: man:systemd-sysv-generator(8)"
      exit 0
    else
      echo "     Active: inactive (dead)"
      exit 3
    fi
    ;;
  start|stop)
    unit="${1:-}"
    name="${unit%.service}"
    if [[ "$cmd" == start ]]; then
      echo running > "$FRM_DEMO_STATE_DIR/$name"
    else
      echo down > "$FRM_DEMO_STATE_DIR/$name"
    fi
    ;;
  *)
    echo "unsupported mock systemctl command: $cmd" >&2
    exit 1
    ;;
esac
''',
        True,
    )

    write(
        mockbin / "ps",
        r'''#!/usr/bin/env bash
set -u
root="$FRM_INSTANCES_DIR"
state="$FRM_DEMO_STATE_DIR"
if grep -q running "$state/ohs_portal"; then
  echo "5101 1 httpd /opt/oracle/ohs/bin/httpd -d $root/ohs_portal/config/fmwconfig/components/OHS/instances/ohs_portal -k start"
  echo "5102 5101 httpd /opt/oracle/ohs/bin/httpd -d $root/ohs_portal/config/fmwconfig/components/OHS/instances/ohs_portal -k start"
  echo "5103 5101 httpd /opt/oracle/ohs/bin/httpd -d $root/ohs_portal/config/fmwconfig/components/OHS/instances/ohs_portal -k start"
fi
if grep -q running "$state/ohs_api"; then
  echo "5201 1 httpd /opt/oracle/ohs/bin/httpd -d $root/ohs_api/config/fmwconfig/components/OHS/instances/ohs_api -k start"
  echo "5202 5201 httpd /opt/oracle/ohs/bin/httpd -d $root/ohs_api/config/fmwconfig/components/OHS/instances/ohs_api -k start"
fi
''',
        True,
    )

    # Mock sudo so auto mode stays deterministic if needed.
    write(
        mockbin / "sudo",
        r'''#!/usr/bin/env bash
if [[ "${1:-}" == "-n" && "${2:-}" == "true" ]]; then
  exit 1
fi
if [[ "${1:-}" == "-n" ]]; then shift; fi
exec "$@"
''',
        True,
    )

    return admin, state, mockbin


def run_command(argv, env, max_lines=None):
    proc = subprocess.run(
        argv,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    out = proc.stdout.rstrip("\n")
    if max_lines is not None:
        lines = out.splitlines()
        if len(lines) > max_lines:
            out = "\n".join(lines[:max_lines] + ["…"])
    return out, proc.returncode


def cast_event(t, text):
    return [round(t, 3), "o", text]


def main():
    with tempfile.TemporaryDirectory(prefix="frm-demo-") as tmp:
        base = pathlib.Path(tmp)
        admin, state, mockbin = setup_fixture(base)

        env = os.environ.copy()
        env.update(
            {
                "PATH": str(mockbin) + os.pathsep + env.get("PATH", ""),
                "FRM_INSTANCES_DIR": str(admin),
                "FRM_DEMO_STATE_DIR": str(state),
                "FRM_COLOR": "always",
                "FRM_SUDO": "never",
                "FRM_POLL_INTERVAL": "0.1",
                "FRM_TIMEOUT": "5",
                "FRM_HANDLERS_FILE": str(base / "no-handlers.sh"),
                "TERM": "xterm-256color",
            }
        )

        scenes = [
            ("frm list --long", [str(FRM), "list", "--long"], None, ["ohs_api", "ohs_legacy_11119", "ohs_portal"]),
            ("frm status --summary", [str(FRM), "status", "--summary"], None, ["ohs_api", "DOWN", "running=2", "down=1"]),
            ("frm ports 'ohs_*'", [str(FRM), "ports", "ohs_*"], None, ["https:8443,http:7777", "8080", "8090"]),
            ("frm plan restart 'ohs_*'", [str(FRM), "plan", "restart", "ohs_*"], None, ["systemctl stop ohs_portal.service", "opmnctl stop"]),
            ("frm --dry-run restart ohs_portal", [str(FRM), "--dry-run", "restart", "ohs_portal"], None, ["systemctl stop ohs_portal.service", "systemctl start ohs_portal.service"]),
            ("frm --dry-run restart --state RUNNING 'ohs_*'", [str(FRM), "--dry-run", "restart", "--state", "RUNNING", "ohs_*"], None, ["ohs_legacy_11119", "ohs_portal"]),
            ("frm start ohs_api", [str(FRM), "start", "ohs_api"], None, ["ohs_api is RUNNING", "pid=5201"]),
            ("frm status --json ohs_api", [str(FRM), "status", "--json", "ohs_api"], None, ['"state":"RUNNING"', '"backend":"systemd"']),
            ("frm help status", [str(FRM), "help", "status"], 16, ["STATUS", "FRM chooses the best available status backend"]),
        ]

        events = []
        t = 0.2
        events.append(cast_event(t, "\x1b[1;36mFRM 0.1.1\x1b[0m  Fronten Runtime Manager\r\n\r\n"))

        for idx, (display, argv, max_lines, expected) in enumerate(scenes):
            if idx in {2, 5}:
                t += 0.7
                events.append(cast_event(t, "\x1b[2J\x1b[H"))
            t += 0.45
            events.append(cast_event(t, f"\x1b[1;35m$\x1b[0m {display}\r\n"))
            output, rc = run_command(argv, env, max_lines=max_lines)
            output = output.replace(str(admin), "/u01/app/oracle/admin")
            for needle in expected:
                if needle not in output:
                    raise RuntimeError(f"demo command {display!r} missing expected text {needle!r}:\n{output}")
            if rc not in (0, 2):
                raise RuntimeError(f"demo command {display!r} failed with rc={rc}:\n{output}")
            t += 0.45
            if output:
                events.append(cast_event(t, output.replace("\n", "\r\n") + "\r\n"))
            t += 1.2

        header = {
            "version": 2,
            "width": 105,
            "height": 28,
            "timestamp": 1789507200,  # 2026-09-15 release demo; deterministic
            "env": {"SHELL": "/bin/bash", "TERM": "xterm-256color"},
            "title": "FRM - Fronten Runtime Manager",
        }

        with CAST.open("w") as f:
            f.write(json.dumps(header, separators=(",", ":")) + "\n")
            for event in events:
                f.write(json.dumps(event, separators=(",", ":")) + "\n")

        print(CAST)


if __name__ == "__main__":
    main()
