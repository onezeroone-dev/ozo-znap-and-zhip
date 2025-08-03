# OZO Znap and Zhip Installation, Configuration, and Usage
## Overview
This script automates the use of `zfs send|receive` to take and ship snapshots of ZFS file systems over SSH and performs snapshot maintenance. It runs with no arguments. When executed, it iterates through the *CONF* files in `/etc/ozo-znap-and-zhip.conf.d` and runs each valid job. It runs on the _target_ (backup) system and invokes `zfs send` on the the _source_ (production) systems. This makes it especially useful for performing backups of remote _source_ systems on a network that has a dynamic gateway IP. It also provides a means of creating ZFS filesystems on _source_ systems and performing an _origin_ (initial) snapshot that serves as the basis for all future incremental snapshots. It will also take an initial _origin_ snapshot for existing ZFS filesystems.

## Prerequisites
Designate a _target_ system to store ZFS snapshots. Install the SSH client and ZFS, and create a _Zpool_ to store ZFS snapshots. Identify a _source_ system with a Zpool that may or may not already have a Zvol you wish to back up.

## Installation
To install this script on your system, you must first register the One Zero One repository.

### AlmaLinux 10, Red Hat Enterprise Linux 10, Rocky Linux 10 (RPM)
```bash
rpm -Uvh https://repositories.onezeroone.dev/el/10/noarch/onezeroone-release-latest.el10.noarch.rpm
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-ONEZEROONE
dnf repolist
dnf -y install ozo-znap-and-zhip
```

### Debian (DEB)
PENDING.

## Configuration
### Configure Znap and Zhip Jobs
Using `/etc/ozo-znap-and-zhip.conf.d/ozo-znap-and-zhip-host.conf.example` as a template, create a configuration file for each of your source system(s).

|Variable|Value|Description|
|--------|-----|-----------|
|SSHPORT|`22`|SSH port.|
|SUSER|`root`|Source host username.|
|SHOSTFQDN|`host.example.com`|Source fully-qualified domain name.|
|SZPOOL|`Source-pool`|Source Zpool name.|
|SZVOL|`example`|Source Zvol name.|
|SCOMPRESSION|`on`|Source Zvol compression setting (on|off).|
|SDEDUP|`off`|Source Zvol deduplication setting (on|off).|
|SVOLBLOCKSIZE|`64k`|Source Zvol block size in kilobytes/|
|SSIZE|`1GB`|Remove Zvol size with units (MB|GB|TB).|
|SHISTORY|`3`|Number of snapshots to keep on the source system.|
|DZPOOL|`target-pool`|Target Zpool name.|
|DHISTORY|`180`|Number of snapshots to keep on the target system.|

### Configure Cron
Modify `/etc/cron.d/ozo-znap-and-zhip` to suit your scheduling needs. The default configuration runs `ozo-znap-and-zhip.sh` every day at 5:00am.

### SSH Setup
On the _source_ system (as `root`):

* Generate SSH keys for the `root` user:

    `ssh keygen`

* Install your `root` user SSH keys to each of the source system(s) with e.g.:

    `ssh-copy-id -i root@rdiff-host.example.com`

## Usage
```
ozo-znap-and-zhip
    <String>
```

## Examples
```bash
ozo-znap-and-zhip.sh /etc/ozo-znap-and-zhip.conf.d/ozo-znap-and-zhip-host.conf.example
```

## Notes
Please visit [One Zero One](https://onezeroone.dev) to learn more about my other work.
