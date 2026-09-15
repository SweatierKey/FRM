# Architecture

FRM keeps discovery, state collection, presentation and lifecycle execution separate.
This avoids making backend-specific output part of the public CLI contract.

## Flow

```text
/u01/app/oracle/admin
        |
        v
  discovery/classification
        |
        v
 selection + exclusions
        |
        +--------------------+
        |                    |
        v                    v
 status backend          action backend
 handler                 handler
 OPMN                    OPMN
 systemd                 systemd
 SysV                    SysV
 process fallback
        |                    |
        v                    v
 normalized state       execute action
 RUNNING/DOWN/...             |
        |                     v
        |                wait/verify state
        v
 table / JSON / TSV
```

## Status backend order

1. Custom `<instance>_status` handler.
2. OPMN when `<instance>/bin/opmnctl` exists.
3. systemd unit named `<instance>.service`.
4. SysV init script.
5. Direct process detection.

## Lifecycle backend order

1. Custom `<instance>_start` / `<instance>_stop` handler.
2. OPMN.
3. systemd.
4. SysV.

Custom handlers allow local conventions to override FRM without modifying the main
script. Put them in `~/.config/frm/handlers.sh` or set `FRM_HANDLERS_FILE`.

## State model

- `RUNNING`: positive runtime confirmation.
- `DOWN`: positive confirmation that the runtime is down.
- `WARNING`: contradictory signals, for example OPMN down while a matching httpd exists.
- `UNKNOWN`: backend output could not be interpreted reliably.

Only `RUNNING` is considered healthy for the `status` exit code and for successful
start verification.

## Why process validation matters on OHS 12c

A generated systemd unit for a SysV launcher can remain `active (exited)` because the
launcher itself exits after spawning the actual OHS runtime. FRM therefore associates
real `httpd` processes with the instance directory before declaring the runtime healthy.

## Why OHS 11g process detection is different

In the observed 11g layout, the `httpd.worker` master command line may not contain the
instance path. Instance-specific `odl_rotatelogs` children do contain it. FRM uses their
PPID to identify the corresponding master and then counts its direct HTTP workers.
