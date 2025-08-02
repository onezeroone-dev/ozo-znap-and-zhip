#!/bin/bash
# Script Name: ozo-znap-and-zhip.sh
# Version    : 1.0.0
# Description: This script automates the use of zfs send|receive to take and ship snapshots of ZFS file systems over SSH and performs snapshot maintenance. It also provides a means of creating ZFS filesystems on source systems and performing an origin (initial) snapshot that serves as the basis for all future incremental snapshots.
# Usage      : /usr/sbin/ozo-znap-and-zhip.sh
# Author     : Andy Lievertz <alievertz@onezeroone.dev>
# Link       : https://github.com/onezeroone-dev/ozo-znap-and-zhip/blob/main/README.md

# FUNCTIONS
function ozo-log {
    # Function   : ozo-log
    # Description: Logs output to the system log
    # Arguments  :
    #   LEVEL    : The log level. Allowed values are "err", "info", or "warning". Defaults to "info".
    #   MESSAGE  : The message to log.
    
    # Determine if LEVEL is null
    if [[ -z "${LEVEL}" ]]
    then
        # Level is null; set to "info"
        LEVEL="info"
    fi
    # Determine if MESSAGE is not null
    if [[ -n "${MESSAGE}" ]]
    then
        # Message is not null; log the MESSAGE with LEVEL
        logger -p local0.${LEVEL} -t "OZO Znap and Zhip" "${MESSAGE}"
    fi
}

function ozo-validate-configuration {
    # Function   : ozo-validate-configuration
    # Description: Performs a series of configuration checks. Returns 0 (TRUE) if all checks pass and 1 (FALSE) if any check fails.
    local RETURN=0
    # Iterate through all user-defined variables
    for USERDEFVAR in SUSER SHOSTFQDN SZPOOL SZVOL SCOMPRESSION SDEDUP SVOLBLOCKSIZE SSIZE SHISTORY DZPOOL DHISTORY
    do
        # Determine if the variable is not set
        if [[ -z "${!USERDEFVAR}" ]]
        then
            # Variable is not set; log
            LEVEL="err" MESSAGE="User-defined variable ${USERDEFVAR} is not set." ozo-log
            RETURN=1
        fi
    done
    # Determine if user is root
    if [[ $(id -u) == 0 ]]
    then
        # User is root; determine if local zfolder does not exist
        if ! zfs list -H -o name ${DZPOOL}/${DZFOLDER}
        then
            # Local zfolder does not exist; determine if attempt to create fails
            if ! zfs create ${DZPOOL}/${DZFOLDER}
            then
                # Attempt to create fails; log
                LEVEL="err" MESSAGE="Unable to create local zfolder ${DZPOOL}/${HOSTNAME}." ozo-log
                RETURN=1
            fi
        fi
        # Determine if the SSH binary exists
        if which ssh
        then
            # SSH binary exists; determine if SSH with keys is possible
            if ssh -p ${SSHPORT} -o BatchMode=yes ${SUSER}@${SHOSTFQDN} true
            then
                # SSH with keys is possible; determine if the remote system does not have ZFS
                if ! ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} which zfs
                then
                    LEVEL="err" MESSAGE="Remote host ${SHOSTFQDN} is missing ZFS." ozo-log
                    RETURN=1
                fi
            else
                LEVEL="err" MESSAGE="Unable to SSH to ${SHOSTFQDN} with keys." ozo-log
                RETURN=1
            fi
        else
            LEVEL="err" MESSAGE="Local system is missing SSH." ozo-log
            RETURN=1
        fi
        # Determine if the local ZFS binary does not exist
        if ! which zfs
        then
            # Local ZFS binary does not exist
            LEVEL="err" MESSAGE="Local system is missing ZFS." ozo-log
            RETURN=1
        fi
    else
        # User is not root; log
        LEVEL="err" MESSAGE="Please run this script as root." ozo-log
        RETURN=1
    fi
    # Return
    return ${RETURN}
}

function ozo-verify-szvol {
    # Function   : ozo-verify-szvol
    # Description: Checks if the source ZVOL exists and attempts to create if missing. Returns 0 (TRUE) if ZVOL exists or is successfully created and 1 (FALSE) if unable to create.

    # Control variable
    local RETURN=0
    # Determine if Zvol exists on source
    if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -H -o name ${SZPOOL}/${SZVOL}
    then
        # Zvol exists; log
        LEVEL="info" MESSAGE="Found ${SZPOOL}/${SZVOL} on ${SHOSTFQDN}." ozo-log
    else
        # Zvol does not exist; determine if attempt to create succeeds
        if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs create -s -o compression=${SCOMPRESSION} -o dedup=${SDEDUP} -o volblocksize=${SVOLBLOCKSIZE} -V ${SSIZE} ${SZPOOL}/${SZVOL}
        then
            # Success; log
            LEVEL="info" MESSAGE="Created ZVOL ${SZPOOL}/${SZVOL} on ${SHOSTFQDN}." ozo-log
        else
            # Failure; log
            LEVEL="err" MESSAGE="Unable to create ${SZPOOL}/${SZVOL} on ${SHOSTFQDN}." ozo-log
            RETURN=1
        fi
    fi
    # Return
    return ${RETURN}
}

function ozo-sznap {
    # Function    : ozo-sznap
    # Description : Creates a snapshot on the source using ssh. Returns 0 (TRUE) on successful creation and 1 (FALSE) on failure
    # Arguments
    #    SSNAPSHOT: The name of the snapshot to create

    # Control variable
    local RETURN=0
    # Determine if attempt to create snapshot is successful
    if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs snapshot ${SSNAPSHOT}
    then
        # Success; log
        LEVEL="info" MESSAGE="Created snapshot ${SSNAPSHOT} on ${SHOSTFQDN}." ozo-log
    else
        # Failure; log
        LEVEL="err" MESSAGE="Failed to create snapshot ${SSNAPSHOT} on ${SHOSTFQDN}." ozo-log
        RETURN=1
        
    fi
    # Return
    return ${RETURN}
}

function ozo-szhip {
    # Function    : ozo-szhip
    # Description : Ships a snapshot. Returns 0 (TRUE) on successful shipping and 1 (FALSE) on failure.
    # Arguments
    #    SSENDOPTS:
    #    SLASTSNAP:
    #    SSNAPSHOT:

    # Control variable
    local RETURN=0
    # Log
    LEVEL="info" MESSAGE="Attempting to ship snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}." ozo-log
    # Determine if attempt to ship succeeds
    if ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs send ${SSENDOPTS} ${SSNAPLAST} ${SSNAPSHOT} | zfs recv -ev ${DZPOOL}/${DZFOLDER}
    then
        # Success
        LEVEL="info" MESSAGE="Shipped snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}."
    else
        # Failure
        LEVEL="error" MESSAGE="Error shipping snapshot ${SSNAPSHOT} from ${SHOSTFQDN} to ${DZPOOL}/${DZFOLDER}." ozo-log
        RETURN=1
    fi
    # Return
    return ${RETURN}
}

function ozo-count-ssnapshots {
    # Function   : ozo-count-ssnapshots
    # Description: Counts source Zvol snapshots

    # Return a count of snapshots from the source
    echo $(ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -t snapshot -H -o name ${SZPOOL}/${SZVOL} | wc -l)
}

function ozo-count-dsnapshots {
    # Function   : ozo-count-dsnapshots
    # Description: Counts target Zvol snapshots

    # Return a count of snapshots from the target
    echo $(zfs list -t snapshot -H -o name ${DZPOOL}/${DZFOLDER} | wc -l)
}

function ozo-verify-origin {
    # Function   : ozo-verify-origin
    # Description: Determines if the "@origin" exists and if not, snaps and ships

    # Control variable
    local RETURN=0
    # Obtain the count of source snapshots
    local SSNAPCOUNT=$(ozo-count-ssnapshots)
    # Determine if the source Zvol has zero snapshots
    if [[ "${SSNAPCOUNT}" == "0" ]]
    then
        # Source has zero snapshots; log
        LEVEL="info" MESSAGE="ZVOL ${SZPOOL}/${SZVOL} has no snapshots; attempting to snap and ship the @origin snapshot." ozo-log
        # Determine if attempt to create the "@origin" snapshot succeeds
        if SSNAPSHOT="${SZPOOL}/${SZVOL}@origin" ozo-sznap
        then
            # Success; determine if attempt to send fails
            if ! SSENDOPTS="-p" SSNAPLAST="" SSNAPSHOT="${SZPOOL}/${SZVOL}@origin" ozo-szhip
            then
                # Attempt to send failed
                LEVEL="err" MESSAGE="Attempt to ship origin snapshot failed." ozo-log
                RETURN=1
            fi
        else
            LEVEL="err" MESSAGE="Attempt to create origin snapshot failed."
            RETURN=1
        fi
    else
        # Source has one or more snapshots
        LEVEL="info" MESSAGE="ZVOL ${SZPOOL}/${SZVOL} has snapshots; skipping the @origin snap and ship."
    fi
    # Return
    return ${RETURN}
}

function ozo-znap-and-zhip {
    # Function   : ozo-znap-and-zhip
    # Description: Determines the most recent snapshot on the source; takes and ships an incremental snapshot. Returns 0 (TRUE) on success and 1 (FALSE) on failure.

    # Control variable
    local RETURN=0
    # Determine name of most recent source snapshot
    SSNAPLAST="$(ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -t snapshot -H -o name ${SZPOOL}/${SZVOL} | tail -n 1)"
    # Determine name of snapshot
    SSNAPSHOT="${SZPOOL}/${SZVOL}@${SHOSTFQDN}-$(TZ='Europe/London' date +%Y%m%d-%H%M%S)"
    # Determine if attempt to snapshot succeeds
    if SSNAPSHOT=${SSNAPSHOT} ozo-sznap
    then
        # Success; log
        LEVEL="info" MESSAGE="shipping with ${SSENDOPTS} ${SSNAPLAST} ${SSNAPSHOT}" ozo-log
        # Determine if attempt to ship does not succeed
        if ! SSENDOPTS="-p -i" SSNAPLAST="${SSNAPLAST}" SSNAPSHOT="${SSNAPSHOT}" ozo-szhip
        then
            # Attempt to ship failed
            LEVEL="err" MESSAGE="Attempt to ship failed." ozo-log
            RETURN=1
        fi
    else
        # Failure; log
        LEVEL="err" MESSAGE="Attempt to snap failed." ozo-log
        RETURN=1
    fi
    # Return
    return ${RETURN}
}

function ozo-snapshot-smaintenance {
    # Function   : ozo-snapshot-smaintenance
    # Description: Performs source host snapshot maintenance. Returns 0 (TRUE) on success and 1 (FALSE) on failure.

    # Control variable
    local RETURN=0
    # Determine count of source snapshots
    local SSNAPCOUNT=$(ozo-count-ssnapshots)
    # Log
    LEVEL="info" MESSAGE="Beginning source snapshot maintenance." ozo-log
    # Determine if the count of source snapshots is greater than the desired count
    if [[ "${SSNAPCOUNT}" > "${SHISTORY}" ]]
    then
        # Count is higher; iterate through the snapshots that are older than the desired history date
        for OSNAPSHOT in $( ssh -p ${SSHPORT} ${SUSER}@${SHOSTFQDN} zfs list -t snapshot -H -o name -s creation ${SZPOOL}/${SZVOL} | head -n -${SHISTORY} )
        do
            # Destroy the snapshot
            ssh -p ${SSHPORT} ${USER}@${SHOSTFQDN} zfs destroy ${OSNAPSHOT}
        done
    else
        # Count is not higher
        LEVEL="info" MESSAGE="Number of snapshots found (${SSNAPCOUNT}) is less than or equal to configured snapshot history value (${SHISTORY}); no maintenance required."
    fi
    # Return
    return ${RETURN}
}

function ozo-snapshot-dmaintenance {
    # Function   : ozo-snapshot-dmaintenance
    # Description: Performs target snapshot maintenance. Returns 0 (TRUE) on success and 1 (FALSE) on failure.

    # Control variable
    local RETURN=0
    # Determine count of target snapshots
    local DSNAPCOUNT=$(ozo-count-dsnapshots)
    # Log
    LEVEL="info" MESSAGE="Beginning destination snapshot maintenance." ozo-log
    # Determine if count of snapshots is higher than desired count
    if [[ "${DSNAPCOUNT}" > "${DHISTORY}" ]]
    then
        # Count is higher; iterate through the snapshots older than desired data
        for OSNAPSHOT in $( zfs list -t snapshot -H -o name -s creation ${SZPOOL}/${SZVOL} | head -n -${DHISTORY} )
        do
            # Destroy the snapshot
            zfs destroy ${OSNAPSHOT}
        done
    else
        # Count is not higher
        LEVEL="info" MESSAGE="Number of snapshots found (${DSNAPCOUNT}) is less than or equal to configured snapshot history value (${DHISTORY}); no maintenance required."
    fi
    # Return
    return ${RETURN}
}

function ozo-program-loop {
    # Function   : ozo-program-loop
    # Description: Loops through configuration files in CONFDIR and performs the snap, ship, and maintenance.

    # Control variable
    local RETURN=0
    # Iterate through the conf files in CONFDIR
    for CONFIGURATION in $( ls ${CONFDIR}/*conf )
    do
        # Source the configuration
        source "${CONF_DIR}/${CONFIGURATION}"
        DZFOLDER=${SHOSTFQDN}
        # Determine if the configuration validates
        if ozo-validate-configuration
        then
            # Configuration validates; log
            LEVEL="info" MESSAGE="Configuration validates." ozo-log
            # Determine if the source Zvol exists or has been created
            if ozo-verify-szvol
            then
                # Source zvol exists or has been created; log
                LEVEL="info" MESSAGE="Source Zvol exists or has been created." ozo-log
                # Determine if the origin snapshot verifies
                if ozo-verify-origin
                then
                    # Source origin verifies; log
                    LEVEL="info" MESSAGE="Origin snapshot verified." ozo-log
                    # Determine if snap and ship are successful
                    if ozo-znap-and-zhip
                    then
                        # Success; log
                        LEVEL="info" MESSAGE="Created and shipped snapshot." ozo-log
                        # Perform maintenance
                        ozo-snapshot-smaintenance
                        ozo-snapshot-dmaintenance
                    else
                        # Failure; log
                        LEVEL="err" MESSAGE="Error creating and shipping snapshot." ozo-log
                        RETURN=1
                    fi
                else
                    # Source origin does not verify; log
                    LEVEL="err" MESSAGE="Error verifying source origin" ozo-log
                    RETURN=1
                    
                fi
            else
                # Source Zvol does not exist or has not been created
                LEVEL="err" MESSAGE="Source Zvol does not exist or could not be created" ozo-log
                RETURN=1
            fi
        else
            # Configuration failed validation
            LEVEL="err" MESSAGE="Configuration does not validate." ozo-log
            RETURN=1
        fi
    done
}

# MAIN
# Control variable
EXIT=0
# Define variables
CONFDIR="/etc/ozo-znap-and-zhip.conf.d"
# Log a process start message
LEVEL="info" MESSAGE="OZO Znap and Zhip process starting."
# Determine
if ozo-program-loop > /dev/null 2&>1
then
    LEVEL="info" MESSAGE="Finished with success." ozo-log
else
    LEVEL="err" MESSAGES="Finished with errors." ozo-log
    EXIT=1
fi
# Log a process complete message
LEVEL="info" MESSAGE="OZO Znap and Zhip process complete."
# Exit
exit $EXIT
