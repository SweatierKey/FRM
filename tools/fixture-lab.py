#!/usr/bin/env python3
"""Build deterministic fake OHS estates for FRM development/tests.

No production code depends on this tool. It creates an isolated admin tree plus
mock commands (`opmnctl`, `systemctl`, `ps`) so maintainers can reproduce mixed
11g/12c conditions without access to Oracle middleware.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
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

    # 11g: one running, one down.
    for name, pid, status in (
        ("ohs_legacy_a", "3101", "Alive"),
        ("ohs_legacy_b", "N/A", "Down"),
    ):
        inst = admin / name
        (inst / "bin").mkdir(parents=True, exist_ok=True)
        (state / f"{name}.status").write_text(status + "\n", encoding="utf-8")
        write_executable(
            inst / "bin" / "opmnctl",
            textwrap.dedent(
                f"""\
                #!/usr/bin/env bash
                state_file={state / (name + '.status')!s}
                status="$(cat \"$state_file\")"
                pid={pid!r}
                case "$1" in
                  status)
                    if [[ "$status" == "Alive" ]]; then pid={pid!r}; else pid=N/A; fi
                    cat <<OUT
                Processes in Instance: {name}
                ---------------------------------+--------------------+---------+---------
                ias-component                    | process-type       |     pid | status
                ---------------------------------+--------------------+---------+---------
                ohs1                             | OHS                | $pid | $status
                OUT
                    ;;
                  start) echo Alive > "$state_file" ;;
                  stop) echo Down > "$state_file" ;;
                  *) exit 2 ;;
                esac
                """
            ),
        )

    # 12c: one running and one stopped, represented through fake systemd + ps.
    for name, running, pid in (
        ("ohs_modern_a", True, 4101),
        ("ohs_modern_b", False, 4201),
    ):
        inst = admin / name
        (inst / "bin").mkdir(parents=True, exist_ok=True)
        (inst / "bin" / "startNodeManager.sh").write_text("#!/bin/sh\n", encoding="utf-8")
        (inst / "config/fmwconfig/components/OHS/instances" / name).mkdir(parents=True, exist_ok=True)
        (inst / "config/fmwconfig/components/OHS/instances" / name / "httpd.conf").write_text(
            f"Listen {8440 + (pid % 10)}\n", encoding="utf-8"
        )
        (state / f"{name}.running").write_text("1\n" if running else "0\n", encoding="utf-8")
        (state / f"{name}.pid").write_text(f"{pid}\n", encoding="utf-8")

    systemctl = f'''#!/usr/bin/env bash
state={state}
unit=""
for arg in "$@"; do [[ "$arg" == *.service ]] && unit="$arg"; done
name="${{unit%.service}}"
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
  start) echo 1 > "$state/$name.running" ;;
  stop) echo 0 > "$state/$name.running" ;;
  *) exit 1 ;;
esac
'''
    write_executable(bin_dir / "systemctl", systemctl)

    ps_script = f'''#!/usr/bin/env python3
from pathlib import Path
state = Path({str(state)!r})
admin = Path({str(admin)!r})
print("  PID  PPID COMMAND         COMMAND")
for f in sorted(state.glob("ohs_modern_*.running")):
    name = f.stem
    if f.read_text().strip() != "1":
        continue
    pid = int((state / (name + ".pid")).read_text().strip())
    path = admin / name / "config/fmwconfig/components/OHS/instances" / name
    print(f"{{pid:5d}}     1 httpd           /oracle/ohs/bin/httpd -d {{path}} -k start")
    print(f"{{pid+1:5d}} {{pid:5d}} httpd           /oracle/ohs/bin/httpd -d {{path}} -k start")
'''
    write_executable(bin_dir / "ps", ps_script)

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
    parser.add_argument("--force", action="store_true", help="reuse an existing directory")
    args = parser.parse_args()

    root = args.directory.resolve()
    if root.exists() and any(root.iterdir()) and not args.force:
        raise SystemExit(f"{root} is not empty; use --force or another directory")
    root.mkdir(parents=True, exist_ok=True)
    manifest = create_estate(root)

    print(json.dumps(manifest, indent=2))
    print("\nRun FRM with:")
    print(f"  PATH={manifest['bin_dir']}:$PATH FRM_INSTANCES_DIR={manifest['instances_dir']} ./frm status")


if __name__ == "__main__":
    main()
