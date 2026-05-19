# openshift-kpatch

Proof of concept for deploying kernel livepatches (kpatch) to OpenShift nodes via a privileged DaemonSet.

## Current State

This PoC demonstrates that kpatch modules can be installed and loaded on CoreOS-based OpenShift nodes by:

1. Bundling pre-built `kpatch` and `kpatch-patch` RPMs into a container image.
2. Deploying a privileged DaemonSet that uses `nsenter` to access the host namespaces.
3. Installing the RPMs via `rpm-ostree install --apply-live`.
4. Manually staging the `.ko` module and loading it with `insmod` (since rpm-ostree does not run RPM scriptlets).
5. Enabling `kpatch.service` so patches persist across reboots.

The current implementation is hardcoded to a single kernel version (`5.14.0-570.94.1.el9_6.x86_64`) and a specific kpatch-patch RPM. Updating to a new patch requires rebuilding the container image with new RPMs and editing several variables.

## Proposed: Kernel Version Agnostic DaemonSet

To move beyond this proof of concept, the DaemonSet should be made kernel version agnostic and should manage the full kpatch lifecycle automatically. Specifically:

### Dynamic Repo Enablement

Rather than bundling RPMs in the container image, the entrypoint should enable the appropriate RHEL kpatch repositories on the host (e.g. `rhel-9-for-x86_64-kpatch-rpms`) and use `dnf`/`rpm-ostree` to query and install packages dynamically. This removes the need to rebuild and redeploy the image each time a new kpatch is released.

### Automatic Kernel Version Detection

The entrypoint should detect the running kernel version at startup and resolve the correct `kpatch-patch-<kernel_version>` package name dynamically instead of comparing against a hardcoded `TARGET_KVER`. This allows a single image to work across nodes running different kernel versions during rolling upgrades.

### Continuous Lifecycle Management

Instead of a one-shot install followed by `sleep infinity`, the DaemonSet should periodically:

- Check whether a newer kpatch-patch RPM is available for the running kernel.
- Install and load the latest patch when one is found.
- Verify the livepatch is active via `/sys/kernel/livepatch/` and report status.
- Handle kernel upgrades gracefully — when the node reboots into a new kernel, detect the change and apply the appropriate patch for the new version.

This turns the DaemonSet into a kpatch operator that keeps nodes patched with the latest available livepatch without manual intervention.
