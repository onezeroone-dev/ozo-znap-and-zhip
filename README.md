# ozo-znap-and-zhip

What this does not do:

- Share SSH keys between root users of source and destination

What this DOES do:

- Create a zvol on the production system
- Create and ship an initial snapshot
- Create an incremental snapshot on the production system
- Ship the snapshot to the destination (this system)
- Remove all but a desired number of snapshots on the source
- Remove all but a desired number of snapshots on the destination
