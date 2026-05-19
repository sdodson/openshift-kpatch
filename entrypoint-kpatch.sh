#!/bin/bash
set -euo pipefail

TARGET_KVER="5.14.0-570.94.1.el9_6.x86_64"
KPATCH_RPM="kpatch-0.9.7-3.el9_6.noarch.rpm"
KPATCH_PATCH_RPM="kpatch-patch-5_14_0-570_94_1-1-2.el9_6.x86_64.rpm"
KPATCH_KO="kpatch-5_14_0-570_94_1-1-2.ko"
LIVEPATCH_SYSFS="kpatch_5_14_0_570_94_1_1_2"

host() {
  nsenter -t 1 -m -u -i -n -p -- "$@"
}

RUNNING=$(uname -r)
if [ "$RUNNING" != "$TARGET_KVER" ]; then
  echo "Kernel mismatch: running $RUNNING, need $TARGET_KVER"
  echo "Waiting — the node may still be upgrading/downgrading..."
  sleep infinity
fi

# Ensure kpatch.service is enabled for boot persistence
if ! host systemctl is-enabled kpatch.service &>/dev/null; then
  echo "Enabling kpatch.service..."
  host systemctl enable kpatch.service
fi

# Check if this livepatch is already loaded
if host test -d /sys/kernel/livepatch/${LIVEPATCH_SYSFS} 2>/dev/null; then
  ENABLED=$(host cat /sys/kernel/livepatch/${LIVEPATCH_SYSFS}/enabled 2>/dev/null || echo "unknown")
  echo "Livepatch already loaded (enabled=$ENABLED)"
  sleep infinity
fi

# Wait for any pending rpm-ostree transactions to finish
echo "Waiting for rpm-ostree to be idle..."
while host rpm-ostree status 2>&1 | grep -q "State: busy"; do
  echo "  rpm-ostree busy, retrying in 30s..."
  sleep 30
done

# Install RPMs if not already present
if ! host rpm -q kpatch-patch-5_14_0-570_94_1 2>/dev/null | grep -q "1-2"; then
  echo "Copying RPMs to host /var/tmp/..."
  cp /opt/rpms/${KPATCH_RPM} /host/var/tmp/
  cp /opt/rpms/${KPATCH_PATCH_RPM} /host/var/tmp/

  echo "Installing via rpm-ostree install --apply-live..."
  host rpm-ostree install --apply-live \
    /var/tmp/${KPATCH_RPM} \
    /var/tmp/${KPATCH_PATCH_RPM}

  rm -f /host/var/tmp/${KPATCH_RPM} /host/var/tmp/${KPATCH_PATCH_RPM}
fi

# rpm-ostree doesn't run scriptlets, so populate /var/lib/kpatch/ manually.
# kpatch.service runs "kpatch load --all" which loads from this path on boot.
echo "Staging .ko in /var/lib/kpatch for boot persistence..."
host bash -c "
  mkdir -p /var/lib/kpatch/${TARGET_KVER}
  cp /usr/lib/kpatch/${TARGET_KVER}/${KPATCH_KO} /var/lib/kpatch/${TARGET_KVER}/${KPATCH_KO}
  chcon -t modules_object_t /var/lib/kpatch/${TARGET_KVER}/${KPATCH_KO}
"

# rpm-ostree live-apply puts the .ko on a read-only overlay with SELinux
# label lib_t. The kernel requires modules_object_t for module_load.
# Load from the copy we just placed in /var/lib/kpatch.
echo "Loading livepatch module..."
host insmod /var/lib/kpatch/${TARGET_KVER}/${KPATCH_KO}

# Verify
echo "=== Livepatch status ==="
host kpatch list 2>/dev/null || true
ENABLED=$(host cat /sys/kernel/livepatch/${LIVEPATCH_SYSFS}/enabled 2>/dev/null || echo "unknown")
echo "Livepatch enabled: $ENABLED"

echo "Done. Sleeping to keep DaemonSet pod alive."
sleep infinity
