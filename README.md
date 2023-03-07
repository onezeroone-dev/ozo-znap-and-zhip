# ozo-znap-and-zhip

What this does not do:

- Share SSH keys between root users of production and backup
- Create a zvol on the production system
- Create and ship an initial snapshot

What this DOES do:

- Create snapshot on the production system
- Ship the snapshot to the backup system (this system)
- Remove the snapshot from the production system
- Perform maintenance on the backup system

Relevant links:

- [zfslib](https://pypi.org/project/zfslib)
