#!/bin/bash

#######################################
# user-defined variables
CONFDIR="/etc/ozo-znap-and-zhip.conf.d"
#######################################

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
      if ssh -p ${SSHPORT} -o BatchMode=yes ${SUSER}@${SHOSTFQDN} true
      then
        # check that the remote system has zfs
        if ! ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} which zfs
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
  if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -H -o name ${SZPOOL}/${SZVOL}
  then
    # zvol exists; log
    LEVEL="info" MESSAGE="Found ${SZPOOL}/${SZVOL} on ${SHOSTFQDN}." ozo-log
  else
    # ZVOL does not exist; attempt to create
    if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs create -s -o compression=${SCOMPRESSION} -o dedup=${SDEDUP} -o volblocksize=${SVOLBLOCKSIZE} -V ${SSIZE} ${SZPOOL}/${SZVOL}
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
  if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs snapshot ${SSNAPSHOT}
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
  if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs send ${SSENDOPTS} ${SSNAPLAST} ${SSNAPSHOT} | zfs recv -ev ${DZPOOL}/${DZFOLDER}
  then
    # ship success
    LEVEL="info" MESSAGE="Shipped snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}."
  else
    # ship failure
    RETURN=1
    LEVEL="error" MESSAGE="Error shipping snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}." ozo-log
  fi
  return ${RETURN}
}

function ozo-count-ssnapshots {
  ### Counts source ZVOL snapshots
  echo $(ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -t snapshot -H -o name ${SZPOOL}/${SZVOL} | wc -l)
}

function ozo-count-dsnapshots {
  ### Counts local ZVOL snapshots
  echo $(zfs list -t snapshot -H -o name ${DZPOOL}/${DZFOLDER} | wc -l)
}

function ozo-verify-origin {
  ### Determines if the "@origin" exists and if not, snaps and ships
  local RETURN=0
  local SSNAPCOUNT=$(ozo-count-ssnapshots)
  # check if source ZVOL has zero snapshots
  if [[ "${SSNAPCOUNT}" == "0" ]]
  then
    # zero snapshots; attempt to create the "@origin" snapshot
    LEVEL="info" MESSAGE="ZVOL ${SZPOOL}/${SZVOL} has no snapshots; attempting to snap and ship the @origin snapshot." ozo-log
    if SSNAPSHOT="${SZPOOL}/${SZVOL}@origin" ozo-sznap
    then
      # created successfully; attempt to ship
      if ! SSENDOPTS="-p" SSNAPLAST="" SSNAPSHOT="${SZPOOL}/${SZVOL}@origin" ozo-szhip
      then
        RETURN=1
      fi
    fi
  else
    LEVEL="info" MESSAGE="ZVOL ${SZPOOL}/${SZVOL} has snapshots; skipping the @origin snap and ship."
  fi
  return ${RETURN}
}

function ozo-znap-and-zhip {
  ### Determines the most recent snapshot on the source
  ### Takes and ships an incremental snapshot
  ### Returns 0 (TRUE) on success and 1 (FALSE) on failure
  local RETURN=0
  SSNAPLAST="$(ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -t snapshot -H -o name ${SZPOOL}/${SZVOL} | tail -n 1)"
  SSNAPSHOT="${SZPOOL}/${SZVOL}@${SHOSTFQDN}-$(TZ='Europe/London' date +%Y%m%d-%H%M%S)"
  # attempt to snap
  if SSNAPSHOT=${SSNAPSHOT} ozo-sznap
  then
    # attempt to ship
    LEVEL="info" MESSAGE="shipping with ${SSENDOPTS} ${SSNAPLAST} ${SSNAPSHOT}" ozo-log
    if ! SSENDOPTS="-p -i" SSNAPLAST="${SSNAPLAST}" SSNAPSHOT="${SSNAPSHOT}" ozo-szhip
    then
      RETURN=1
    fi
  else
    RETURN=1
  fi
  return ${RETURN}
}

function ozo-snapshot-smaintenance {
  ### Performs source host snapshot maintenance
  ### Returns 0 (TRUE) on success and 1 (FALSE) on failure
  local RETURN=0
  local SSNAPCOUNT=$(ozo-count-ssnapshots)
  LEVEL="info" MESSAGE="Beginning source snapshot maintenance." ozo-log
  if [[ "${SSNAPCOUNT}" > "${SHISTORY}" ]]
  then
    for OSNAPSHOT in $( ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -t snapshot -H -o name -s creation ${SZPOOL}/${SZVOL} | head -n -${SHISTORY} )
    do
      ssh -p ${SSHPORT} ${USER}@${SHOSTFQDN} zfs destroy ${OSNAPSHOT}
    done
  else
    LEVEL="info" MESSAGE="Number of snapshots found (${SSNAPCOUNT}) is less than or equal to configured snapshot history value (${SHISTORY}); no maintenance required."
  fi
  return ${RETURN}
}

function ozo-snapshot-dmaintenance {
  ### Performs destination host snapshot maintenance
  ### Returns 0 (TRUE) on success and 1 (FALSE) on failure
  local RETURN=0
  local DSNAPCOUNT=$(ozo-count-dsnapshots)
  LEVEL="info" MESSAGE="Beginning destination snapshot maintenance." ozo-log
  if [[ "${DSNAPCOUNT}" > "${DHISTORY}" ]]
  then
    for OSNAPSHOT in $( zfs list -t snapshot -H -o name -s creation ${SZPOOL}/${SZVOL} | head -n -${DHISTORY} )
    do
      zfs destroy ${OSNAPSHOT}
    done
  else
    LEVEL="info" MESSAGE="Number of snapshots found (${DSNAPCOUNT}) is less than or equal to configured snapshot history value (${DHISTORY}); no maintenance required."
  fi
  return ${RETURN}  
}

function ozo-program-loop {
  ### Loops through configuration files in CONFDIR and performs the snap, ship, and maintenance
  local RETURN=0
  for CONFIGURATION in $( ls ${CONFDIR}/*conf )
  do
    source "${CONF_DIR}/${CONFIGURATION}"
    DZFOLDER=${SHOSTFQDN}
    # call the configuration function
    if ozo-validate-configuration
    then
      # configuration validates; log; call the check source zvol function
      LEVEL="info" MESSAGE="Configuration validates." ozo-log
      if ozo-verify-szvol
      then
        # source zvol exists or has been created; log and verify the origin snapshot
        LEVEL="info" MESSAGE="Source ZVOL verified." ozo-log
        if ozo-verify-origin
        then
          # source origin verifies; log; call znap and zhip
          LEVEL="info" MESSAGE="Origin snapshot verified." ozo-log
          if ozo-znap-and-zhip
          then
            # snap and ship was successful; log
            LEVEL="info" MESSAGE="Created and shipped snapshot." ozo-log
            # perform maintenance
            ozo-snapshot-smaintenance
            ozo-snapshot-dmaintenance
          else
            RETURN=1
            LEVEL="err" MESSAGE="Error creating and shipping snapshot." ozo-log
          fi
        else
          RETURN=1
          LEVEL="err" MESSAGE="Error verifying source origin" ozo-log
        fi
      else
        RETURN=1
        LEVEL="err" MESSAGE="Error verfiying source ZVOL" ozo-log
      fi
    else
      RETURN=1
      LEVEL="err" MESSAGE="Configuration does not validate." ozo-log
    fi
  done
}

# MAIN

if ozo-program-loop > /dev/null 2&>1
then
  LEVEL="info" MESSAGE="Finished with success." ozo-log
  exit 0
else
  LEVEL="err" MESSAGES="Finished with errors." ozo-log
  exit 1
fi
