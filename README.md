# OZO Znap and Zhip

## Overview

This script automates the use of `zfs send|receive` to take and ship snapshots of ZFS file systems over SSH. It also performs snapshot maintenance. It runs with no arguments. When invoked, it iterates through the *CONF* files in `CONFDIR` (e.g., `/etc/ozo-rdiff-backup.conf.d`) and executes each valid job.

This script runs on the *destination* (backup) system and invokes `zfs send` on the the *source* (production) systems. This makes it especially useful for performing backups of remote *source* systems through a firewall or on a network that has a dynamic gateway IP.

It also provides a means of creating ZFS filesystems on *source* systems and performing an "origin" (initial) snapshot that serves as the basis for all future incremental snapshots. It will also take an initial "origin" snapshot for existing ZFS filesystems.

Please visit https://onezeroone.dev to learn more about this script and my other work.

## Setup and Configuration

Designate a *destination* system. Install the SSH client and ZFS, and create a *zpool* to store snapshots. Identify a *source* system that contains a ZFS filesystem to snap and ship.

### Clone the Repository and Copy Files

Clone this repository to a temporary directory on the ZFS *destination* system. Then (as `root`):

- Copy `ozo-znap-and-zhip.sh` to `/etc/cron.daily` and set permissions to `rwx------` (`0700`)
- Create `/etc/ozo-znap-and-zhip.conf.d`
- Use `host.example.com.conf` as a template to create a *CONF* file in `/etc/ozo-znap-and-zhip.conf.d` for each *source* ZFS filesystem and update with appropriate values:

    |Variable|Example Value|Description|
    |--------|-------------|-----------|
    |SSHPORT|`22`|SSH port for establishing a connection to *source* system|
    |SUSER|`root`|User that invokes `zfs send` on the *source* system|
    |SHOSTFQDN|`"host.example.com"`|Fully qualified domain name of the Remote System|
    |SZPOOL|`"remote-pool"`|Name of the *zpool* on the *source* system|
    |SZVOL|`"example"`|Name of the ZFS filesystem on the *source* to snap and ship|
    |SCOMPRESSION|`"on"`|Enable or disable compression when creating this ZFS filesystem on the *source* system. Valid values are *on* and *off*.|
    |SDEDUP|`"off"`|Enable or disable deduplication when creating this ZFS filesystem on the *source* system.|
    |SVOLBLOCKSIZE|`"64k"`|Volume block size to use when creating this ZFS filesystem on the *source* system. Typical values are 4k, 16k, 64k, 256k, etc.|
    |SSIZE|`"1GB"`|Size of ZFS filesystem on the *source* system with units (MB|GB|TB)|
    |SHISTORY|`"3"`|Number of snapshots to keep on the *source* system|
    |DZPOOL|`"local-pool"`|Name of the *zpool* on the *destination* system|
    |DHISTORY|`180`|Number of snapshots to keep on the *destination* system|

### SSH Setup

On the *destination* system (as `root`):

- Generate SSH keys for the `root` user:

    `# ssh keygen`

- Install your `root` user SSH keys to each of the Remote System(s) with e.g.:

    `ssh-copy-id -i root@rdiff-host.example.com`
