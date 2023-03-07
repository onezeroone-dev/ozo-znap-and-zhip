# ozo-znap-and-zhip

What this does not do:

- Create a zvol on the source system
- Create and ship an initial snapshot

What this DOES do:

- Create snapshot on the production system
- Ship the snapshot to the backup system (this system)
- Perform production and backup snapshot maintenance
