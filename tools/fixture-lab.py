#!/usr/bin/env python3
"""Build a deterministic fake OHS estate for FRM development and smoke tests.

No production code depends on this tool. It creates an isolated admin tree plus
mock commands (opmnctl, systemctl, ps, ss and OHS httpd binaries) so maintainers
can exercise mixed 11g/12c status, lifecycle, configtest and listener validation
without access to Oracle middleware.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import stat
import textwrap


def write_executable(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def create_estate(root: Path) -> dict:
    admin = root / "admin"
    bin_dir = root / "bin"
    state = root / "state"
    for p in (admin, bin_dir, state):
        p.mkdir(parents=True, exist_ok=True)

    httpd = bin_dir / "httpd"
    httpd_worker = bin_dir / "httpd.worker"
    syntax_script = """#!/usr/bin/env bash
if [[ " $* " == *" -t "* ]]; then
    echo 'Syntax OK'
    exit 0
fi
exit 0
"""
    write_executable(httpd, syntax_script)
    write_executable(httpd_worker, syntax_script)

    # 11g: one running, one down. Lifecycle follows the current OPMN policy.
    for name, pid, status_value, port in (
        ("ohs_legacy_a", 3101, "Alive", 7786),
        ("ohs_legacy_b", 3201, "Down", 7787),
    ):
        inst = admin / name
        (inst / "bin").mkdir(parents=True, exist_ok=True)
        conf_dir = inst / "config/OHS/ohs1"
        conf_dir.mkdir(parents=True, exist_ok=True)
        (conf_dir / "httpd.conf").write_text(f"Listen {port}\n", encoding="utf-8")
        log_dir = inst / "diagnostics/logs/OHS/ohs1"
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / "error.log").write_text(f"{name} legacy error sample\n", encoding="utf-8")
        (log_dir / "access.log").write_text(f"{name} legacy access sample\n", encoding="utf-8")
        (state / f"{name}.status").write_text(status_value + "\n", encoding="utf-8")
        (state / f"{name}.pid").write_text(str(pid) + "\n", encoding="utf-8")

        write_executable(
            inst / "bin" / "opmnctl",
            textwrap.dedent(
                f"""\
                #!/usr/bin/env bash
                state_file={str(state / (name + '.status'))!r}
                pid_file={str(state / (name + '.pid'))!r}
                status="$(cat "$state_file")"
                pid="$(cat "$pid_file")"
                case "${{1:-}}" in
                  status)
                    [[ "$status" == Alive ]] || pid=N/A
                    if [[ "${{2:-}}" == -l ]]; then
                      cat <<OUT
                Processes in Instance: {name}
                ias-component | process-type | pid | status | ports
                ohs1 | OHS | $pid | $status | http:{port}
                OUT
                    else
                      cat <<OUT
                Processes in Instance: {name}
                ias-component | process-type | pid | status
                ohs1 | OHS | $pid | $status
                OUT
                    fi
                    ;;
                  stopall|stopproc)
                    echo Down > "$state_file"
                    ;;
                  startall|startproc)
                    next=$(( $(cat "$pid_file") + 100 ))
                    echo "$next" > "$pid_file"
                    echo Alive > "$state_file"
                    ;;
                  start)
                    : # OPMN daemon start; component remains in its current state
                    ;;
                  *) exit 2 ;;
                esac
                """
            ),
        )

    # 12c: one running and one stopped, represented through fake systemd + ps.
    for name, running, pid, port in (
        ("ohs_modern_a", True, 4101, 8441),
        ("ohs_modern_b", False, 4201, 8442),
    ):
        inst = admin / name
        (inst / "bin").mkdir(parents=True, exist_ok=True)
        (inst / "bin" / "startNodeManager.sh").write_text("#!/bin/sh\n", encoding="utf-8")
        conf_dir = inst / "config/fmwconfig/components/OHS/instances" / name
        conf_dir.mkdir(parents=True, exist_ok=True)
        (conf_dir / "httpd.conf").write_text(f"Listen {port}\n", encoding="utf-8")
        log_dir = inst / "servers" / name / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / "error_log-2026-09-16-00:00").write_text(f"{name} modern error sample\n", encoding="utf-8")
        (log_dir / "access_log-2026-09-16-00:00").write_text(f"{name} modern access sample\n", encoding="utf-8")
        (state / f"{name}.running").write_text("1\n" if running else "0\n", encoding="utf-8")
        (state / f"{name}.pid").write_text(f"{pid}\n", encoding="utf-8")
        (state / f"{name}.port").write_text(f"{port}\n", encoding="utf-8")

    systemctl = f'''#!/usr/bin/env bash
state={state}
name=""
for arg in "$@"; do
  case "$arg" in
    ohs_*) name="${{arg%.service}}" ;;
  esac
done
[[ -n "$name" ]] || exit 1
case "$1" in
  show)
    [[ -f "$state/$name.running" ]] || {{ echo 'LoadState=not-found'; exit 0; }}
    echo 'LoadState=loaded'
    ;;
  is-active)
    [[ "$(cat "$state/$name.running" 2>/dev/null)" == 1 ]] && echo active && exit 0
    echo inactive; exit 3
    ;;
  status)
    if [[ "$(cat "$state/$name.running" 2>/dev/null)" == 1 ]]; then
      echo "● $name.service - SYSV: OHS."
      echo '     Active: active (exited)'
      exit 0
    fi
    echo "● $name.service - SYSV: OHS."
    echo '     Active: inactive (dead)'
    exit 3
    ;;
  start)
    next=$(( $(cat "$state/$name.pid") + 100 ))
    echo "$next" > "$state/$name.pid"
    echo 1 > "$state/$name.running"
    ;;
  stop) echo 0 > "$state/$name.running" ;;
  *) exit 1 ;;
esac
'''
    write_executable(bin_dir / "systemctl", systemctl)

    ps_script = f'''#!/usr/bin/env python3
from pathlib import Path
import sys

state = Path({str(state)!r})
admin = Path({str(admin)!r})
httpd = {str(httpd)!r}
httpd_worker = {str(httpd_worker)!r}

rows = []
for status_file in sorted(state.glob("ohs_legacy_*.status")):
    name = status_file.stem
    if status_file.read_text().strip() != "Alive":
        continue
    pid = int((state / (name + ".pid")).read_text().strip())
    conf = admin / name / "config/OHS/ohs1/httpd.conf"
    rows.append(("oracle", pid, 1, "httpd.worker", f"{{httpd_worker}} -DSSL", 600))
    rows.append(("oracle", pid + 1, pid, "odl_rotatelogs", f"/oracle/ohs/bin/odl_rotatelogs {{admin/name}}/diagnostics/logs/OHS/ohs1/error.log", 600))
    rows.append(("oracle", pid + 2, pid, "httpd.worker", f"{{httpd_worker}} -DSSL", 600))

for running_file in sorted(state.glob("ohs_modern_*.running")):
    name = running_file.stem
    if running_file.read_text().strip() != "1":
        continue
    pid = int((state / (name + ".pid")).read_text().strip())
    path = admin / name / "config/fmwconfig/components/OHS/instances" / name
    conf = path / "httpd.conf"
    args = f"{{httpd}} -DOHS_MPM_EVENT -d {{path}} -k start -f {{conf}}"
    rows.append(("oracle", pid, 1, "httpd", args, 300))
    rows.append(("oracle", pid + 1, pid, "httpd", args, 300))
    nm_pid = pid + 50
    nm_args = f"/oracle/jdk/bin/java -Dweblogic.RootDirectory={{admin/name}} weblogic.NodeManager -v"
    rows.append(("oracle", nm_pid, 1, "java", nm_args, 3600))

args = sys.argv[1:]
if "-p" in args:
    try:
        wanted = int(args[args.index("-p") + 1])
    except Exception:
        wanted = -1
    match = next((r for r in rows if r[1] == wanted), None)
    if match and any("etimes=" in a for a in args):
        print(match[5])
    elif match and any("etime=" in a for a in args):
        seconds = match[5]
        print(f"{{seconds // 60:02d}}:{{seconds % 60:02d}}")
    sys.exit(0)

fmt = " ".join(args)
for user, pid, ppid, comm, cmd, elapsed in rows:
    if "user=,pid=,ppid=,etime=,args=" in fmt:
        print(f"{{user}} {{pid}} {{ppid}} {{elapsed//60:02d}}:{{elapsed%60:02d}} {{cmd}}")
    elif "pid=,ppid=,comm=,args=" in fmt:
        print(f"{{pid}} {{ppid}} {{comm}} {{cmd}}")
    elif "pid=,ppid=,comm=" in fmt:
        print(f"{{pid}} {{ppid}} {{comm}}")
    elif "pid=,args=" in fmt:
        print(f"{{pid}} {{cmd}}")
    else:
        print(f"{{pid}} {{ppid}} {{comm}} {{cmd}}")
'''
    write_executable(bin_dir / "ps", ps_script)

    ss_script = f'''#!/usr/bin/env python3
from pathlib import Path
state = Path({str(state)!r})
print('State Recv-Q Send-Q Local Address:Port Peer Address:Port Process')
for f in sorted(state.glob('ohs_modern_*.running')):
    name = f.stem
    if f.read_text().strip() != '1':
        continue
    pid = int((state / (name + '.pid')).read_text().strip())
    port = int((state / (name + '.port')).read_text().strip())
    print(f'LISTEN 0 128 0.0.0.0:{{port}} 0.0.0.0:* users:(("httpd",pid={{pid}},fd=7))')
for f in sorted(state.glob('ohs_legacy_*.status')):
    name = f.stem
    if f.read_text().strip() != 'Alive':
        continue
    pid = int((state / (name + '.pid')).read_text().strip())
    port = 7786 if name.endswith('_a') else 7787
    print(f'LISTEN 0 128 0.0.0.0:{{port}} 0.0.0.0:* users:(("httpd.worker",pid={{pid}},fd=7))')
'''
    write_executable(bin_dir / "ss", ss_script)

    manifest = {
        "instances_dir": str(admin),
        "bin_dir": str(bin_dir),
        "state_dir": str(state),
        "instances": ["ohs_legacy_a", "ohs_legacy_b", "ohs_modern_a", "ohs_modern_b"],
    }
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="output fixture directory")
    parser.add_argument("--force", action="store_true", help="replace an existing fixture directory")
    args = parser.parse_args()

    root = args.directory.resolve()
    if root.exists() and any(root.iterdir()):
        if not args.force:
            raise SystemExit(f"{root} is not empty; use --force or another directory")
        shutil.rmtree(root)
    root.mkdir(parents=True, exist_ok=True)
    manifest = create_estate(root)

    print(json.dumps(manifest, indent=2))
    print("\nRun FRM with:")
    print(f"  PATH={manifest['bin_dir']}:$PATH FRM_INSTANCES_DIR={manifest['instances_dir']} ./frm status")


if __name__ == "__main__":
    main()
