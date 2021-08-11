#!/bin/bash
# micrologs.sh - collates logs of a session from pods/debug directories & creates a tarball
#
# Usage: (follow the onscreen directions from the portal)
#         bash INSTALLDIR/hpcem/scripts/micrologs.sh $timestamp
#
# Prerequisites:
# ~/hpcemlogs is present - this script should be run in there. Etiquette expectation to avoid
# logs being saved in different locations by different people.
#
# !!!!!!! THIS SCRIPT NEEDS to be run post "su - root" AS IT NEEDS TO RUN kubectl !!!!!!!

SCRIPT_ABS_PATH=$(realpath "$0")
SCRIPT_DIR="/opt/hpcem/hpcem/scripts"
. "${SCRIPT_DIR}/helpers"

# Need timestamp as a parameter to proceed
if [ $# -ne 1 ]; then
    echo "USAGE: bash INSTALLDIR/hpcem/scripts/micrologs.sh <timestamp>"
    exit 1
fi

TS=$1
K=$(which kubectl)
CONF=${TS}_config.txt
CHK=${TS}_checkpoints.txt

# Where to get the logs from?
LOGS_DIR="${HPCEM_DEBUG_DIR}"  # Preferred, if available
LOGS_DIR_GO="/go/bin/"
LOGS_DIR_JAVA="/opt/springboot8/"
 
# Create directory with the name of timestamp & copy files specific to our timestamp within
mkdir -p ${TS}
cp -f ${CONF} ${TS}/config
if [ -f ${CHK} ]; then # Checkpoint file may not always be present
    cp -f ${CHK} ${TS}/checkpoints
fi
# With segmented logging support, our file format is as follows:
# If single file, it'll be ${TS}_ui.txt
# If multiple files, it'll be ${TS}-1_ui.txt, ${TS}-2_ui.txt, ...
if [ -f ${TS}_ui.txt ]; then
    cp ${TS}_ui.txt ${TS}/UI.log
else
    # All files will be numbered from 1 onwards in sequence
    for (( count=1 ; ; count++ )) ; do
        file=${TS}-${count}_ui.txt
        if [ -f $file ]; then
            cp $file ${TS}/UI-$count.log
        else
	    # If file with current sequence is not found, no more files to copy
            break
        fi
    done
fi

# TODO: Move upstairs code to "mv" when we're fully ready

# Add names of the services to pull logs from here - must be unique, obviously
declare -A SERVICENAME_MAP
SERVICENAME_MAP[Agent]="Agent"
SERVICENAME_MAP[AlertsService]="alerts-notifications-service"
SERVICENAME_MAP[ArgonAuth]="argon-auth"
SERVICENAME_MAP[AuditLog]="auditlog-processor-service"
SERVICENAME_MAP[AUTH]="AUTH"
SERVICENAME_MAP[CCS]="common-config-service"
SERVICENAME_MAP[DashboardService]="dashboard-service"
SERVICENAME_MAP[DCGW]="lhdcgw"
SERVICENAME_MAP[ES]="es"
SERVICENAME_MAP[Groups]="group-processing-service"
SERVICENAME_MAP[GroupService]="group-service"
SERVICENAME_MAP[LHIDM]="lhidm"
SERVICENAME_MAP[LHSERVER]="lhserver"
SERVICENAME_MAP[PolicyManagementService]="policy-management-service"
SERVICENAME_MAP[PushNotificationService]="push-notification-service"
SERVICENAME_MAP[SMS]="server-metrics-service"
SERVICENAME_MAP[SearchService]="search-service"
SERVICENAME_MAP[TaskService]="task-service"
SERVICENAME_MAP[TemplateService]="template-service"
SERVICENAME_MAP[SUS]="software-update-service"

# First we check when the debug directory exists
if [ -d ${LOGS_DIR} ]; then
    # It exists, but should not be empty
    if [ -n "$(ls -A ${LOGS_DIR})" ]; then
        echo "Getting logs from ${LOGS_DIR}"
    else
        echo "${LOGS_DIR} is empty - will get logs from kubectl"
        LOGS_DIR=""
    fi
else
    echo "${LOGS_DIR} doesn't exist - will get logs from kubectl"
    LOGS_DIR=""
fi

# Get all the logs to collect from each pod (prefer the common log location, if one exists)
for SERVICE in $(cat ${CONF}); do
    if [[ ! -z "${LOGS_DIR}" ]]; then
        LOG_FILE=${LOGS_DIR}/${TS}_${SERVICE}.log
        cp -f ${LOG_FILE} ${TS}/${SERVICE}.log
        # Uncomment below line to conserve space by removing the file after successful copy
        #test $? -eq 0 && rm -f ${LOG_FILE} ${TS}/${SERVICE}.log
    else
        POD_NAME=$($K get pod -A | grep ${SERVICENAME_MAP[${SERVICE}]} | sed 's/  */ /g' | cut -f2 -d " ")
        # TODO: Support multiple pods
        if [ "$SERVICE" != "DashboardService" ]; then
            LOG_FILE=${LOGS_DIR_GO}${TS}_${SERVICE}.log
        else
            LOG_FILE=${LOGS_DIR_JAVA}${TS}_${SERVICE}.log
        fi
        ${K} cp daas/${POD_NAME}:${LOG_FILE} ${TS}/${SERVICE}.log
        # Uncomment below line to conserve space by removing the file after successful copy
        # FIXME: Have to add the success / fail criteria to "cp" before removing file
        # ${K} exec -it $POD_NAME - n daas rm ${LOG_FILE}
    fi
done

# Finally create a tarball
tar cvfj ${TS}.tar.bz2 ${TS}

info "${TS}.tar.bz2"
# TODO: Upload tarball to a location

