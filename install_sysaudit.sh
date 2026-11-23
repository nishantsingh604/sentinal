#!/usr/bin/env bash
# One-time deployment helper. Run as root:  sudo ./install_sysaudit.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

id auditmanager >/dev/null 2>&1 || useradd -m -s /bin/bash auditmanager
command -v setfacl >/dev/null || { apt-get install -y acl >/dev/null 2>&1 || yum install -y acl; }

install -d -o auditmanager -g auditmanager -m 750 /course_project /course_project/audit
install -d -o auditmanager -g auditmanager -m 755 /opt/sysaudit
install -o auditmanager -g auditmanager -m 640 /dev/null /var/log/sysaudit_daemon.log 2>/dev/null || \
    { touch /var/log/sysaudit_daemon.log; chown auditmanager:auditmanager /var/log/sysaudit_daemon.log; chmod 640 /var/log/sysaudit_daemon.log; }

install -o auditmanager -g auditmanager -m 750 sysaudit.sh security.sh \
        BK_scheduler.sh Bandhna.K.sh logging.sh error_handler.sh storage_check.sh /opt/sysaudit/

install -o auditmanager -g auditmanager -m 644 sysaudit.cfg /opt/sysaudit/

install -m 644 systemd/sysaudit.service systemd/sysaudit-cleanup.service systemd/sysaudit.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now sysaudit.service
systemctl enable --now sysaudit.timer
echo "Done. Check: systemctl status sysaudit.service sysaudit.timer"