#!/usr/bin/env bash
set -euo pipefail

echo __SELINUX_BEFORE__
getenforce 2>/dev/null || true
getsebool use_nfs_home_dirs 2>/dev/null || true

echo __REQUESTING_SUDO__
sudo -v
sudo setsebool -P use_nfs_home_dirs 1

echo __SELINUX_AFTER__
getsebool use_nfs_home_dirs 2>/dev/null || true

echo __SELINUX_NFS_HOME_FIXED__

