#!/bin/bash

ssh root@trei.zenastronave.com zfs snapshot trei-pool/plex@trei-20230307-032100
ssh root@trei.zenastronave.com zfs send -p trei-pool/plex@trei-20230307-032100 | zfs recv -ev mini-pool/trei