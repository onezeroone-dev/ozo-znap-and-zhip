#!/bin/bash

DATETIME=$(TZ="Europe/London" date +%Y%m%d-%H%M%S)

#source
ssh root@trei.zenastronave.com zfs create -s -o compression=on -o dedup=off -o volblocksize=64k -V 60GB trei-pool/plex

ssh -o BatchMode=yes root@trei.zenastronave.com true
ssh root@trei.zenastronave.com zfs snapshot trei-pool/plex@trei-20230307-032100

# initial znap n zhip (-p)
ssh root@trei.zenastronave.com zfs send -p trei-pool/plex@trei-20230307-032100 | zfs recv -ev mini-pool/trei

# subsequent (incremental) znap n zhips (-p -i)
ssh root@trei.zenastronave.com zfs send -p trei-pool/plex@trei-20230307-032100 | zfs recv -ev mini-pool/trei
