#!/bin/bash

# user-defined variables
SUSER="root"
SHOSTFQDN="trei.zenastronave.com"
SZPOOL="trei-pool"
SZVOL="plex2"
SCOMPRESSION="on"
SDEDUP="off"
SVOLBLOCKSIZE="64k"
SSIZE="1GB"
SHISTORY=3
DZPOOL="mini-pool"
DHISTORY=180

# derived variables
DZFOLDER=${SHOSTFQDN}

# FUNCTIONS

function ozo-log {
  ### Logs output to the system log
  if [[ -z "${LEVEL}" ]]
  then
    LEVEL="info"
  fi
  if [[ -n ${MESSAGE} ]]
  then
    logger -p local0.${LEVEL} -t "OZO Znap and Zhip ${SZVOL}" "${MESSAGE}"
  fi
}

function ozo-validate-configuration {
  ### Performs a series of checks
  ### Returns 0 (TRUE) if all checks pass
  ### Returns 1 (FALSE) if any check fails
  local RETURN=0
  # check that all user-defined variables are set
  for USERDEFVAR in SUSER SHOSTFQDN SZPOOL SZVOL SCOMPRESSION SDEDUP SVOLBLOCKSIZE SSIZE SHISTORY DZPOOL DHISTORY
  do
    if [[ -z "${!USERDEFVAR}" ]]
    then
      RETURN=1
      LEVEL="err" MESSAGE="User-defined variable ${USERDEFVAR} is not set." ozo-log
    fi
  done
  # check that the script is run as root
  if [[ $(id -u) == 0 ]]
  then
    # script is run as root; check that local zfolder exists
    if ! zfs list -H -o name ${DZPOOL}/${DZFOLDER}
    then
      # local zfolder does not exist; attempt to create
      if ! zfs create ${DZPOOL}/${DZFOLDER}
      then
        # unable to create local zfolder
        RETURN=1
        LEVEL="err" MESSAGE="Unable to create local zfolder ${DZPOOL}/${HOSTNAME}." ozo-log
      fi
    fi
    # check that the ssh binary exists
    if which ssh
    then
      # check that SSH with keys is possible
      if ssh -o BatchMode=yes ${SUSER}@${SHOSTFQDN} true
      then
        # check that the remote system has zfs
        if ! ssh ${SUSER}@${SHOSTFQDN} which zfs
        then
          RETURN=1
          LEVEL="err" MESSAGE="Remote host ${SHOSTFQDN} is missing ZFS." ozo-log
        fi
      else
        RETURN=1
        LEVEL="err" MESSAGE="Unable to SSH to ${SHOSTFQDN} with keys." ozo-log
      fi  
    else
      LEVEL="err" MESSAGE="Local system is missing SSH." ozo-log
      RETURN=1
    fi
    # check that the local zfs binary exists
    if ! which zfs
    then
      RETURN=1
      LEVEL="err" MESSAGE="Local system is missing ZFS." ozo-log
    fi    
  else
    # script is not run as root; report
    RETURN=1
    LEVEL="err" MESSAGE="Please run this script as root." ozo-log
  fi
  return ${RETURN}
}

function ozo-verify-szvol {
  ### Checks if the source ZVOL exists and attempts to create if missing
  ### Returns 0 (TRUE) if ZVOL exists or is successfully created and 1 (FALSE) if unable to create
  local RETURN=0
  # check if zvol exists on source
  if ssh ${SUSER}@${SHOSTFQDN} zfs list -H -o name ${SZPOOL}/${SZVOL}
  then
    # zvol exists; log
    LEVEL="info" MESSAGE="Found ${SZPOOL}/${SZVOL} on ${SHOSTFQDN}." ozo-log
  else
    # ZVOL does not exist; attempt to create
    if ssh ${SUSER}@${SHOSTFQDN} zfs create -s -o compression=${SCOMPRESSION} -o dedup=${SDEDUP} -o volblocksize=${SVOLBLOCKSIZE} -V ${SSIZE} ${SZPOOL}/${SZVOL}
    then
      # created; log
      LEVEL="info" MESSAGE="Created ZVOL ${SZPOOL}/${SZVOL} on ${SHOSTFQDN}." ozo-log
    else
      # failed to create; log
      LEVEL="err" MESSAGE="Unable to create ${SZPOOL}/${SZVOL} on ${SHOSTFQDN}." ozo-log
      RETURN=1
    fi
  fi 
  return ${RETURN}
}

function ozo-sznap {
  ### Creates a snapshot on the source using ssh; expects SSNAPSHOT
  ### Returns 0 (TRUE) on successful creation and 1 (FALSE) on failure
  local RETURN=0
  # attempt to take a snapshot
  if ssh ${SUSER}@${SHOSTFQDN} zfs snapshot ${SSNAPSHOT}
  then
    # successful snapshot; log
    LEVEL="info" MESSAGE="Created snapshot ${SSNAPSHOT} on ${SHOSTFQDN}." ozo-log
  else
    # failed to snapshot; log
    RETURN=1
    LEVEL="err" MESSAGE="Failed to create snapshot ${SSNAPSHOT} on ${SHOSTFQDN}." ozo-log 
  fi
  return ${RETURN}
}

function ozo-szhip {
  ### Ships a snapshot; expects SSENDOPTS, SLASTSNAP, and SSNAPSHOT
  ### Returns 0 (TRUE) on successful shipping and 1 (FALSE) on failure
  local RETURN=0
  LEVEL="info" MESSAGE="Attempting to ship snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}." ozo-log
  # attempt to ship
  if ssh ${SUSER}@${SHOSTFQDN} zfs send ${SSENDOPTS} ${SLASTSNAP} ${SSNAPSHOT} | zfs recv -ev ${DZPOOL}/${DZFOLDER}
  then
    # ship success
    LEVEL="info" MESSAGE="Shipped snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}."
  else
    # ship failure
    RETURN=1
    LEVEL="error" MESSAGE="Error shipping snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}." ozo-log
  return ${RETURN}
}

function ozo-count-ssnapshots {
  ### Counts source ZVOL snapshots
  ### Returns the number of snapshots
  return $( ssh ${SUSER}@${SHOSTFQDN} zfs list -H -t snapshot -o name ${SZPOOL}/${SZVOL} | wc -l )
}

function ozo-znz-origin {
  ### Determines if the "@origin" exists and if not, snaps and ships
  local RETURN=0
  # check if source ZVOL has zero snapshots
  if [[ $(ozo-count-ssnapshots) == 0 ]]
  then
    # zero snapshots; attempt to create the "@origin" snapshot
    LEVEL="info" MESSAGE="ZVOL ${SZPOOL}/${SZVOL} has no snapshots; attempting to snap and ship the @origin snapshot." ozo-log
    if SSNAPSHOT="${SZPOOL}/${SZVOL}@origin" ozo-sznap
    then
      # created successfully; attempt to ship
      RETURN=$(SSENDOPTS="-p" SSNAPLAST="" SSNAPSHOT="${SZPOOL}/${SZVOL}@origin" ozo-szhip)
    fi
  fi
  return ${RETURN}
}

function ozo-get-slastsnap {
  ### Gets the most recently created snapshot; sets SLASTSNAP
  ### Returns the name of the last snapshot or if none are found, an empty string
  local RETURN=""
  if [[ $(ozo-count-ssnapshots) > 0 ]]
  then
    RETURN="$(ssh ${SUSER}@${SHOSTFQDN} zfs list -t snapshot -H -o name ${SZPOOL}/${SZVOL} | tail -n 1)"
  else
    RETURN=""
  fi
  return ${RETURN}
}

function ozo-znap-and-zhip {
  ### Determines if the "@origin" exists and if not, snaps and ships
  ### Takes and ships an incremental snapshot
  ### Returns 0 (TRUE) on success and 1 (FALSE) on failure
  local RETURN=0
  DATETIME=$(TZ="Europe/London" date +%Y%m%d-%H%M%S)
  SSNAPSHOT="${SZPOOL}/${SZVOL}@${SHOSTFQDN}-${DATETIME}"
  # call ozo-znz-origin to make sure the "@origin" has been snapped and shipped
  if ozo-znz-origin
  then
    # origin exists, attempt to snapshot
    if SSNAPSHOT=${SSNAPSHOT} ozo-sznap
    then
      # attempt to ship
      SLASTSNAP="$(ozo-get-slastsnap)"
      RETURN=$(SSENDOPTS="-p -i" SLASTSNAP=${SLASTSNAP} SSNAPSHOT=${SSNAPSHOT} ozo-szhip)
    else
      RETURN=1
    fi
  else
    RETURN=1
  fi
  return ${RETURN}
}

function ozo-snapshot-maintenance {
  return 0
}

# MAIN

# global variables
EXIT=0

# call the configuration function
if ozo-validate-configuration
then
  echo "configuration"
  # configuration validates; log and call the check source zvol function
  LEVEL="info" MESSAGE="Configuration validates." ozo-log
  if ozo-verify-szvol
  then
    # source zvol exists or has been created; log and call the znap and zhip function
    LEVEL="info" MESSAGE="Source ZVOL verified." ozo-log
    if ozo-znap-and-zhip
    then
      # snap and ship was successful; log
      LEVEL="info" MESSAGE="Created and shipped snapshot." ozo-log
      # perform maintenance
      if ozo-snapshot-maintenance
      then
        LEVEL="info" MESSAGE="Performed snapshot maintenance." ozo-log
      else
        EXIT=1
        LEVEL="err" MESSAGE="Error performing snapshot maintenance." ozo-log
      fi
    else
      EXIT=1
      LEVEL="err" MESSAGE="Error creating and shipping snapshot." ozo-log
    fi
  else
    EXIT=1
    LEVEL="err" MESSAGE="Error verfiying source ZVOL" ozo-log
  fi
else
  EXIT=1
  LEVEL="err" MESSAGE="Configuration does not validate." ozo-log
fi

if [[ ${EXIT} == 0 ]]
then
  LEVEL="info" MESSAGE="Finished with success." ozo-log
else
  LEVEL="err" MESSAGES="Finished with errors." ozo-log

exit ${EXIT}
