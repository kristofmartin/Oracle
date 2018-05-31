#!/bin/bash
# ==============================================================================
# Name         : backup_oracle.ksh
# Description  : Backups a database
#
# Parameters   : -c(onfig) <configuration file>
#                -t(ype): type of backup (L0, L1, ARCH, ARCHEXTRA)
#
#
# Modification History
# ====================
# When      Who               What
# ========= ================= ==================================================
# 18-JUL-17 Wim Janssen       Initial script
# ==============================================================================
#
#set -e #abort when a command fails
export NLS_DATE_FORMAT='YYYY-MM-DD HH24:MI:SS'              #for rman output


PROGNAME=$0
PROGARGUMENTS=$*

# -----------------
# set some defaults
# -----------------
[[ ! -z ${DEBUG} ]]    && set -x
[[ -z ${SLEEP_SECS} ]] && SLEEP_SECS=3                     
[[ -z ${CHANNELS} ]] && CHANNELS=4                         
[[ -z ${ARCH_DEL_HOURS} ]] && ARCH_DEL_HOURS=48            
[[ -z ${ARCH_DEL_TIMES} ]] && ARCH_DEL_TIMES=2             
[[ -z ${ARCHEXTRA_DEL_HOURS} ]] && ARCHEXTRA_DEL_HOURS=${ARCH_DEL_HOURS}   
[[ -z ${ARCHEXTRA_DEL_TIMES} ]] && ARCHEXTRA_DEL_TIMES=${ARCH_DEL_TIMES}              


# ============================================
# thats it, nothing to change below this line!
# ============================================



# ----------------------------------------
# function to right pad text with a leader
# ----------------------------------------
function rpadwait {
    text=$1
    printf "%s" "${text}" | sed -e :a -e 's/^.\{1,88\}$/&\./;ta'
    return 0
}

# function to perform calculations. Useful as it takes scientific notation in its stride. Handy when dealing with very big database and filesystem sizes.
function calc { awk "BEGIN { print $* }"; }

function usage {
    echo "Usage: ${PROGNAME} -c <config file> -t <backup type (L0,L1,ARCH,ARCHEXTRA)>"
    error
}

function error {
  
  newline="\n"
  
  errormessage="${errormessage}${newline} ************"
  errormessage="**script failed**"
  errormessage="${errormessage}${newline} ************"
  errormessage="${errormessage}${newline} hostname: `hostname`"
  errormessage="${errormessage}${newline} scriptname: ${PROGNAME}"
  errormessage="${errormessage}${newline} parameters: ${PROGARGUMENTS}"
  
  echo -e ${errormessage}
  
  exit 1
}

# -------------------------------------
rpadwait "parse command line arguments"
# -------------------------------------

while getopts "t:c:" OPT
do
    case "$OPT" in
    t) BU_TYPE="${OPTARG}";
       ;;
    c) CONFIG="${OPTARG}";
       ;;
    *) usage
       ;;
    esac
done
shift $((OPTIND-1))

##type checken!!! slechts 4 mogelijkheden

unset TYPE_LEVEL0
unset TYPE_LEVEL1
unset TYPE_ARCH
unset TYPE_ARCHEXTRA

if [[ "${BU_TYPE}" == "L0"  ]]; then
  TYPE_LEVEL0=1
elif [[ "${BU_TYPE}" == "L1"  ]]; then
  TYPE_LEVEL1=1
elif [[ "${BU_TYPE}" == "ARCH"  ]]; then
  TYPE_ARCH=1
elif [[ "${BU_TYPE}" == "ARCHEXTRA"  ]]; then
  TYPE_ARCHEXTRA=1  
  TYPE_ARCH=1  
else
  echo "Invalid backup type"
  usage
fi

if [[ ! -r ${CONFIG} ]]; then
    echo "NOK"
    printf "\n%s\n" "Cannot read configuration file ${CONFIG}"
    usage
fi
echo "OK"
sleep ${SLEEP_SECS}

# --------------------------------------------------------------
rpadwait "bring in the config file to setup necessary variables"
# --------------------------------------------------------------
. ${CONFIG}
if [[ $? -ne 0 ]]; then
    echo "NOK"
    printf "\n%s\n" "ERROR There was a problem sourcing in the configuration file (${CONFIG})."
    error
else
    echo "OK"
fi

# -------------------------------------
rpadwait "check basic config variables"
# -------------------------------------
if [[ -z ${SERVICE} ]]; then
    echo "NOK"
    printf "\n%s\n" "Please specify a Service in ${CONFIG}"
    usage
fi

if [[ -z ${RMAN_LOG_DIR} ]]; then
    echo "NOK"
    printf "\n%s\n" "Please specify a RMAN_LOG_DIR in ${CONFIG}"
    usage
fi


if [[ -z ${RMAN_WORK_DIR} ]]; then
    echo "NOK"
    printf "\n%s\n" "Please specify a RMAN_WORK_DIR in ${CONFIG}"
    usage
fi


if [[ -z ${BACKUP_DIR} ]]; then
    echo "NOK"
    printf "\n%s\n" "Please specify a BACKUP_DIR in ${CONFIG}"
    usage
fi


echo "OK"

# ===================
# Prerequisite checks
# ===================
PREREQ_FAIL="false"


# ----------------------------
rpadwait "check oraenv exists"
# ----------------------------
ls /usr/local/bin/oraenv >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    echo "NOK"
    printf "\n%s\n" "ERROR: oraenv does not exist in /usr/local/bin. Was the root.sh script run?"
    PREREQ_FAIL="true"
else
    echo "OK"
fi
sleep ${SLEEP_SECS}

# --------------------------------------
rpadwait "check the directory structure"
# --------------------------------------
mkdir -p ${RMAN_LOG_DIR}
mkdir -p ${RMAN_WORK_DIR}
BACKUP_DIR_database=${BACKUP_DIR}'/database'
mkdir -p ${BACKUP_DIR_database}
BACKUP_DIR_controlfile=${BACKUP_DIR}'/controlfile'
mkdir -p ${BACKUP_DIR_controlfile}
BACKUP_DIR_spfile=${BACKUP_DIR}'/spfile'
mkdir -p ${BACKUP_DIR_spfile}

echo "OK"
sleep ${SLEEP_SECS}


# --------------------------------------
rpadwait "create the rman script"
# --------------------------------------

#creating the header

RMAN_SCRIPT="${RMAN_WORK_DIR}/rman_${SERVICE}_${BU_TYPE}.rman"
rm -f ${RMAN_SCRIPT}
touch ${RMAN_SCRIPT}

RMAN_LOG="${RMAN_LOG_DIR}/rman_${SERVICE}_${BU_TYPE}_`date +%y%m%d_%H%M%S`.rman.log"
rm -f ${RMAN_LOG}
touch ${RMAN_LOG}

#connecting
echo "set echo on" >> ${RMAN_SCRIPT}
echo "spool log to ${RMAN_LOG};"  >> ${RMAN_SCRIPT}

echo "connect target 'rmanbackup/Pf7i1kN98lPAC@${SERVICE} as sysbackup'" >> ${RMAN_SCRIPT}

if [[ ! -z ${RCAT_DB} ]]; then
    echo "connect catalog ${RCAT_OWNER}/${RCAT_OWNER_PWD}@${RCAT_DB}" >> ${RMAN_SCRIPT}

fi

#start of run blok
echo "run" >> ${RMAN_SCRIPT} 
echo "{" >> ${RMAN_SCRIPT} 


    #allocate channels
    i=0
    while [[ $i -lt ${CHANNELS} ]]; do
            echo "allocate channel 'c${i}' type DISK;" >> ${RMAN_SCRIPT}
            (( i += 1 ))
    done
    
    #in case of an ARCHEXTRA, we first do some cleanup before taking the archive backup (TYPE_ARCH).  The deletion policy is based on specific parameters
    if [[ ! -z ${TYPE_ARCHEXTRA} ]]; then
      echo "delete noprompt archivelog until time 'sysdate-${ARCHEXTRA_DEL_HOURS}/24' backed up ${ARCHEXTRA_DEL_TIMES} times to disk;"  >> ${RMAN_SCRIPT} 
    fi  
      
    #backup according to type
    if [[ ! -z ${TYPE_LEVEL0} ]]; then
      echo "backup incremental level = 0 format '${BACKUP_DIR_database}/db_lvl0_%T_%U' tag = 'level0' database plus archivelog not backed up format '${BACKUP_DIR_database}/arc_%e_%T_%U' tag='archivelog' ;"  >> ${RMAN_SCRIPT}
    elif [[ ! -z ${TYPE_LEVEL1} ]]; then
      echo "backup incremental level = 1 format '${BACKUP_DIR_database}/db_lvl1_%T_%U' tag = 'level1' database plus archivelog not backed up format '${BACKUP_DIR_database}/arc_%e_%T_%U' tag='archivelog' ;"  >> ${RMAN_SCRIPT}
    elif [[ ! -z ${TYPE_ARCH} ]]; then
      echo "backup format '${BACKUP_DIR_database}/arc_%e_%T_%U' tag = 'archivelog' archivelog all not backed up ${ARCH_DEL_TIMES} times;"  >> ${RMAN_SCRIPT}
    fi
        
    #backup controlfile
    echo "backup format '${BACKUP_DIR_controlfile}/controlfile_%T_%U' tag='controlfilebackup' current controlfile;" >> ${RMAN_SCRIPT} 
    
    #backup spfile
    echo "backup format '${BACKUP_DIR_spfile}/spfile_%T_%U' tag='spfilebackup' spfile;" >> ${RMAN_SCRIPT} 
    
    #cleanup archivelogs
    echo "delete noprompt archivelog until time 'sysdate-${ARCH_DEL_HOURS}/24' backed up ${ARCH_DEL_TIMES} times to disk;"  >> ${RMAN_SCRIPT} 
    
    
#end of run blok    
echo "}" >> ${RMAN_SCRIPT} 


echo "delete noprompt obsolete;" >> ${RMAN_SCRIPT}

echo "OK"


sleep ${SLEEP_SECS}

# --------------------------------
rpadwait "set the environment"
# --------------------------------

ORAENV_ASK=NO

export ORACLE_SID=dummy
. oraenv >> /dev/null

echo "OK (TODO: werkt niet indien sid niet bestaat, zou error moeten geven)"

sleep ${SLEEP_SECS}

# --------------------------------------
rpadwait "check the rman script syntax"
# --------------------------------------

rman checksyntax cmdfile=${RMAN_SCRIPT} > /tmp/results.$$ 2>&1

grep 'RMAN-' /tmp/results.$$ >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
    echo "NOK"
    printf "\n%s\n" "ERROR: Failed syntax check for RMAN command file ${RMAN_SCRIPT}. Please investigate."
    cat /tmp/results.$$ && rm -f /tmp/results.$$
    error
else
    echo "OK" && rm -f /tmp/results.$$
fi

sleep ${SLEEP_SECS}

# --------------------------------------
rpadwait "start the rman script"
# --------------------------------------

rman cmdfile=${RMAN_SCRIPT} log=${RMAN_LOG} 

grep 'RMAN-' ${RMAN_LOG}  >/dev/null 2>&1

if [[ $? -eq 0 ]]; then
    echo "NOK"
    printf "\n%s\n" "ERROR: Backup ${SERVICE} failed (${RMAN_SCRIPT}). Please investigate (${RMAN_LOG})."
    error
else
    echo "OK"
fi

sleep ${SLEEP_SECS}

exit









