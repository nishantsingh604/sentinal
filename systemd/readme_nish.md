# Member 4: systemd Service, User Sandboxing, and Access Delegation

CIS 341 Fall 2026 - System Health Monitor & Security Auditing Daemon

| Requirement | Topic | Where it lives |
|---|---|---|
| 2 | Auto-start at boot (systemd) | `systemd/sysaudit.service`, `systemd/sysaudit-cleanup.service`, `systemd/sysaudit.timer`, `install_sysaudit.sh` |
| 11 | Only `auditmanager` may run the program | `security.sh` (`enforce_identity`), `AUTHORIZED_USER` in `sysaudit.cfg` |
| 12 | Delegate / revoke access to another user | `security.sh` (`delegate_access`, `revoke_access`, `list_delegates`), options in `sysaudit.sh` |

---

## 1. What each part does

### Requirement 2 - systemd service
- `sysaudit.service` starts `/opt/sysaudit/sysaudit.sh --daemon` at boot (`WantedBy=multi-user.target`) as the user `auditmanager`.
- It restarts on failure after 10 seconds, but **not** for exit codes 2, 3 and 4 (identity violation, missing config, bad workspace), because retrying those cannot succeed.
- Hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectHome`, `ProtectSystem=strict`, and write access limited to `/course_project/audit` and the log file.
- `sysaudit-cleanup.service` and `sysaudit.timer` run the maintenance job (`BK_scheduler.sh`) at midnight on days 1, 4, 7, ... of the month. The scheduler's own 3-day check decides whether to archive.
- `install_sysaudit.sh` creates the user, folders, log file, installs everything into `/opt/sysaudit/`, and enables the service and timer.

### Requirement 11 - sandboxing
`enforce_identity` reads `AUTHORIZED_USER` from `sysaudit.cfg`, compares it to the current user (`id -un`), and rejects any other user:
- prints `[ERROR] Security violation: user "<name>" is not permitted. Only "auditmanager" may run sysaudit. (exit code 2)` to STDERR
- writes the violation to the system log (`logger`, `auth.warning`) and to the daemon log
- exits with code **2** (`IDENTITY_VIOLATION`)

### Requirement 12 - delegation
Run as `auditmanager`:

| Option | Effect |
|---|---|
| `--delegate USER` | Gives USER read/write/execute (ACL) on `/course_project/audit` |
| `--revoke USER` | Removes that ACL |
| `--list-delegates` | Lists users that have delegated access |

Safety checks: the name must be a valid Linux username, cannot be yourself or `root`, the user must exist, the workspace must exist, and `setfacl` must be installed.

---

## 2. Installation

Run from the project root on **Ubuntu/Debian**:

```bash
sudo apt-get update
sudo apt-get install -y acl
sudo ./install_sysaudit.sh
```

Verify:

```bash
systemctl status sysaudit.service
systemctl status sysaudit.timer
```

The service should show `active (running)` and the timer should show a next run time.

> If you change any script, run `sudo ./install_sysaudit.sh` again so `/opt/sysaudit/` gets the new version.

> **GitHub Codespaces note:** a Codespace normally has no systemd, so the installer will stop at the `systemctl` lines. The user, folders, log and copied scripts are still created. Test the service on a real Ubuntu VM.

---

## 3. Usage

Manual runs must be done as `auditmanager`:

```bash
sudo useradd -m auditor1
sudo runuser -u auditmanager -- /opt/sysaudit/sysaudit.sh --delegate auditor1
sudo runuser -u auditmanager -- /opt/sysaudit/sysaudit.sh --list-delegates
sudo runuser -u auditmanager -- /opt/sysaudit/sysaudit.sh --revoke auditor1
```


```
sudo tail -10 /var/log/sysaudit_daemon.log
```

Expected messages:

```
[OK] Access to /course_project/audit delegated to 'auditor1'.
[OK] Access for 'auditor1' revoked.
user:auditor1:rwx          <- from --list-delegates
(no delegates)             <- when nobody has access
```

---

## 4. Exit codes for this part

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Identity violation (user is not `auditmanager`) |
| 3 | Configuration file missing or `AUTHORIZED_USER` not set |
| 4 | Workspace `/course_project/audit` missing or not a directory |
| 10 | Delegate user does not exist |
| 11 | Invalid delegate target (bad name, yourself, or root) |
| 12 | Failed to apply or revoke the ACL |
| 13 | `setfacl` / `getfacl` not installed |

---

## 5. Testing

### 5.1 Automated test (Requirement 11)

```bash
bash test_sysaudit.sh
```

Test 29 ("Unauthorized User Access") confirms that a non-`auditmanager` user is rejected. Expected: `[PASSED]` and finally `All 29 tests have passed!`.
Note: test 29 passes only when run **as someone other than `auditmanager`**.

### 5.2 Manual tests

Create a helper account first:

```bash
sudo useradd -m auditor1
```

| # | Test | Command | Expected result |
|---|---|---|---|
| 1 | Wrong user is blocked | `./sysaudit.sh --scan-interval 60; echo "exit=$?"` (as your normal user) | `Security violation` message, `exit=2` |
| 2 | Violation is logged | `sudo tail -5 /var/log/sysaudit_daemon.log` or `sudo journalctl -t sysaudit -n 5` | `IDENTITY_VIOLATION` entry |
| 3 | Correct user is allowed | `sudo -u auditmanager /opt/sysaudit/sysaudit.sh --list-delegates` | `(no delegates)`, `exit=0` |
| 4 | Folder permissions | `ls -ld /course_project /course_project/audit` | `drwxr-x--- auditmanager auditmanager` |
| 5 | Outsider cannot read | `sudo runuser -u auditor1 -- ls /course_project/audit` | `Permission denied` |
| 6 | Delegate access | `sudo -u auditmanager /opt/sysaudit/sysaudit.sh --delegate auditor1` | `[OK] Access ... delegated to 'auditor1'.` |
| 7 | Delegate can now read | `sudo runuser -u auditor1 -- ls /course_project/audit` | Listing works, no error |
| 8 | ACL is visible | `getfacl /course_project/audit` and `--list-delegates` | `user:auditor1:rwx` |
| 9 | Revoke access | `sudo -u auditmanager /opt/sysaudit/sysaudit.sh --revoke auditor1` | `[OK] Access for 'auditor1' revoked.` |
| 10 | Access is gone | `sudo runuser -u auditor1 -- ls /course_project/audit` | `Permission denied` again |

### 5.3 Error cases for delegation

Run each as `auditmanager`:

| Command | Expected |
|---|---|
| `--delegate ghost` (user does not exist) | exit **10** |
| `--delegate auditmanager` (yourself) | exit **11** |
| `--delegate root` | exit **11**, "Delegation to root is refused" |
| `--delegate "Bad Name"` (invalid format) | exit **11** |

Check the exit code right after each command with `echo "exit=$?"`.

### 5.4 systemd tests (Requirement 2, on the VM)

```bash
systemctl is-enabled sysaudit.service          # enabled
systemctl is-active sysaudit.service           # active
systemctl show sysaudit.service -p User        # User=auditmanager
ps -eo user,cmd | grep "[s]ysaudit.sh --daemon"   # first column: auditmanager
systemctl list-timers | grep sysaudit          # next run at 00:00
sudo journalctl -u sysaudit.service -n 20      # service output
sudo systemctl start sysaudit-cleanup.service  # run maintenance now
sudo journalctl -u sysaudit-cleanup.service -n 20
```

Boot test (the main proof for Requirement 2):

```bash
sudo reboot
# after logging back in:
systemctl status sysaudit.service              # should be active (running) without starting it manually
```

### 5.5 Cleanup after testing

```bash
sudo userdel -r auditor1
```

---

## 6. Troubleshooting

| Problem | Cause / fix |
|---|---|
| `yum: command not found` during install | `setfacl` was missing. Run `sudo apt-get update && sudo apt-get install -y acl`, then install again. |
| `sudo .\install_sysaudit.sh: command not found` | Backslash is Windows syntax. Use `./install_sysaudit.sh`. |
| `sudo -u auditmanager` asks for a password (Codespaces) | Use `sudo runuser -u auditmanager -- <command>`. |
| Service shows `failed` | `sudo journalctl -u sysaudit.service -n 30` |
| Exit code 13 | `sudo apt-get install -y acl` |
| `systemctl: command not found` / system not booted with systemd | Running in a container (Codespaces). Use the Ubuntu VM. |

---

## 7. Known limitation

`BK_scheduler.sh` (the maintenance job) does not call `enforce_identity`, so the identity check applies to `sysaudit.sh` but not to a manual run of the scheduler. The systemd unit still runs it as `auditmanager`.

---

## Viewing the Log File

The program writes to `/var/log/sysaudit_daemon.log`. Logging starts automatically whenever the program runs, so no separate command is needed to turn it on.

### 1. Generate log entries

Run one scan as `auditmanager`:

```bash
sudo runuser -u auditmanager -- /opt/sysaudit/sysaudit.sh --storage-limit 50
```

On a normal Ubuntu VM, `sudo -u auditmanager` works in place of `runuser`.

### 2. Display the log

```bash
sudo cat /var/log/sysaudit_daemon.log          # whole file
sudo tail -20 /var/log/sysaudit_daemon.log     # last 20 lines
sudo tail -f /var/log/sysaudit_daemon.log      # live view (Ctrl+C to stop)
```

### 3. Filter by severity

```bash
sudo grep "\[INFO\]" /var/log/sysaudit_daemon.log
sudo grep "\[WARN" /var/log/sysaudit_daemon.log
sudo grep "\[ERROR\]" /var/log/sysaudit_daemon.log
```

### Log format

Each entry has a timestamp and a severity level:

```
[2026-11-19 10:15:02] [INFO] Identity check passed: running as 'auditmanager'
```

> The file permissions are 640, so `sudo` is needed to read it.


storagr_check:
```
sudo runuser -u auditmanager -- dd if=/dev/zero of=/course_project/audit/big.dat bs=1M count=2 status=none
sudo runuser -u auditmanager -- /opt/sysaudit/sysaudit.sh --storage-limit 1
sudo tail -5 /var/log/sysaudit_daemon.log
sudo rm /course_project/audit/big.dat
```
