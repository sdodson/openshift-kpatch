# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

Deploys kernel livepatches (kpatch) to OpenShift worker nodes via a privileged DaemonSet. The container carries pre-built kpatch RPMs, installs them on the host using `rpm-ostree install --apply-live`, and loads the kernel module via `insmod`. The pod then sleeps forever to keep the DaemonSet alive.

Currently targets kernel `5.14.0-570.94.1.el9_6.x86_64` with kpatch `0.9.7-3.el9_6`.

## Build and Deploy

```bash
# Build the container image
podman build -f Containerfile.kpatch -t quay.io/sdodsonrht/kpatch-5.14.0-570.94.1.el9_6.x86_64:latest .

# Push the image
podman push quay.io/sdodsonrht/kpatch-5.14.0-570.94.1.el9_6.x86_64:latest

# Deploy to an OpenShift cluster
oc apply -f kpatch-daemonset.yaml
```

## Architecture

- **Containerfile.kpatch** — Builds a UBI9-minimal image that bundles the kpatch + kpatch-patch RPMs into `/opt/rpms/`.
- **entrypoint-kpatch.sh** — Runs as the container entrypoint with host PID namespace access (`nsenter -t 1`). Validates kernel version, waits for rpm-ostree to be idle, installs RPMs with `--apply-live`, manually stages the `.ko` to `/var/lib/kpatch/` for boot persistence, loads it via `insmod`, and enables `kpatch.service`.
- **kpatch-daemonset.yaml** — Creates a `kpatch` namespace, ServiceAccount, privileged SCC binding, and DaemonSet targeting worker nodes. Mounts the host root filesystem at `/host`.
- **RPM files** — Pre-downloaded kpatch and kpatch-patch RPMs checked into the repo. Multiple patch versions are present; the Containerfile and entrypoint reference the specific version to deploy.

## Key Details

- The entrypoint uses `nsenter -t 1 -m -u -i -n -p` (wrapped as `host()`) to execute commands in the host's namespaces. All rpm-ostree, systemctl, insmod, and file operations run on the host, not in the container.
- rpm-ostree doesn't run RPM scriptlets, so the entrypoint manually copies the `.ko` module to `/var/lib/kpatch/` and sets the `modules_object_t` SELinux context required by the kernel for module loading.
- When updating to a new kpatch-patch version: update the RPM file, and update `TARGET_KVER`, `KPATCH_RPM`, `KPATCH_PATCH_RPM`, `KPATCH_KO`, and `LIVEPATCH_SYSFS` in `entrypoint-kpatch.sh`, plus the `COPY` line in `Containerfile.kpatch` and the image tag in `kpatch-daemonset.yaml`.
