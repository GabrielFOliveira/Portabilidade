#!/usr/bin/env bash
#
#(0) Portability Script
#------------------------------------------------------------------------------------------------
#(0) Author: Gabriel França
#(0) Email: gabrielfoliveira36@gmail.com
#(0) Creation Date 16/03/2020
#(0) Last update: 21/05/2020
#(0) Version:0.5
#-----------------------------------------------------------------------------------
#(0) Update the portability DB and send it to the databases.
#(0)
#(0)




############################
# Remove old useless files #
############################
_remove_source_files(){
    find ${PORTDIR}/ -iname "BDO_*"  -exec rm -f {} +
    find ${SQL_SECURE}/ -iname "BDO_*"  -exec rm -f {} +
}

############################################################
# Send telegram message with the error or the final report #
############################################################

_send_telegram_msg(){
    msg="[$(hostname)] [$0] [$(date '+%Y-%m-%d %T')] [$(hostname)] $@"

    if [[ "${SENDOPTION}" == "REPORT" ]]; then
        for cid in ${REPORT_TELEGRAM}; do
            ${SEND_TELEGRAM} ${cid} "\`\`\`${msg}\`\`\`"
        done
    elif [[ "${SENDOPTION}" == "ERROR" ]]; then
        for cid in ${ERROR_TELEGRAM}; do
            ${SEND_TELEGRAM} ${cid} "\`\`\`${msg}\`\`\`"
        done
    else
        _log "ERROR: SENDOPTION NOT DEFINED"
    fi
}

#####################################################
# Send the email with the error or the final report #
#####################################################

_send_mail_msg(){
    msg="[$(hostname)] [$0] [$(date +'%Y-%m-%d %H:%M:%S %z')] $@"

    if [[ "${SENDOPTION}" == "REPORT" ]]; then
        for email in ${REPORT_EMAIL}; do
            echo -e ${msg} | mail -s "[$(hostname)]  Portability report $(date +'%Y-%m-%d %H:%M:%S %z')" ${email}
        done
    elif [[ "${SENDOPTION}" == "ERROR" ]]; then
        for email in ${ERROR_EMAIL}; do
            echo -e ${msg} | mail -s "[$(hostname)]  ERROR Portability report $(date +'%Y-%m-%d %H:%M:%S %z'))" ${email}
        done
    else
        _error "SENDOPTION NOT DEFINED"
    fi
}

##########################################
# Log the message in the configured file #
##########################################

_log(){
    echo -e "$(date +'%Y-%m-%d %H:%M:%S %z')   ${1}" >> ${LOG}
}


#####################################################
# Test if the last command exited with a error flag #
#####################################################

_test_error(){
    if [[ "${?}" != "0" ]]; then
        _error "${1}"
    fi

}

###########################################################
# If an error occurred, it will log with error message,   #
# send a telegram message, send a email e stop the script #
###########################################################
_error(){
    local error="${1}"
    _log "ERROR: ${error}"
    echo "$(date +'%Y-%m-%d %H:%M:%S %z')   ERROR: ${error}" >> ${ERRORLOG}
    SENDOPTION="ERROR"
    _send_telegram_msg "ERROR: ${error}."
    _send_mail_msg "ERROR: ${error}"
    exit 1
}

#################################################
# Set the basic configuration to run the script #
#################################################

_basic_conf(){
    # start timer to get final runtime
    starttime="$(date +%s)"
    start="$(date +'%Y-%m-%d %H:%M:%S %z')"
    # Getting the date of the previous day.
    #(On the source portability, the full DB is sent at the end of the day, since this script is meant to run early in the morning, the file used will be date with yesterday date).
    YDATE="$(date -v-1d '+%Y%m%d')"
    YYDATE="$(date -v-2d '+%Y%m%d')"

    #Setting the directory where portability is contained.
    PORTDIR="$(cd $(dirname "$0"); pwd)"

    # Path of the script to send telegram
    SEND_TELEGRAM="${PORTDIR}/send_telegram.sh"

    CHECK_CONF1="1"
    CHECK_CONF2="1"
    cd ${PORTDIR}
    #Getting the remote servers configuration
    CONFIG="$(ls  | grep 'portability.conf$')"
    if [[ ${CONFIG} == "" ]]; then
        1>&2 echo "msg to STDERR  REMOTE-SERVERS.CONF NOT IMPORTED CORRECTLY"
        exit 1
    fi
    #Getting the basic configuration for the script to work
    source ./portability.conf
    if [[ "${?}" != "0" || "${CHECK_CONF1}" != "0" ]]; then
       1>&2 echo "msg to STDERR  REMOTE-SERVERS.CONF NOT IMPORTED CORRECTLY"
       exit 1
    fi

    source ./remote-servers.conf
    if [[ "${?}" != "0"  || "${CHECK_CONF2}" != "0" ]]; then
       1>&2 echo "msg to STDERR  REMOTE-SERVERS.CONF NOT IMPORTED CORRECTLY"
       exit 1
    fi

    SQL_PATH="$(command -v ${SQL})"
    _test_error "${SQL} NOT INSTALLED"
    SQL_LOCAL="${SQL_PATH} -s -N -u${DBUSER} -p${DBPASS}"
    SQL_DUMP_PATH="$(command -v ${SQL_DUMP})"
    _test_error "${SQL_DUMP} NOT INSTALLED"
    SQL_DUMP_LOCAL="${SQL_DUMP_PATH} --set-gtid-purged=OFF -u${DBUSER} -p${DBPASS}"

    _log "\nPORTABILITY.SH STARTED \n CONFIGURATION FILE: ${CONFIG} \n
    TEMPORARY DATABASE: ${DBSOURCE} \n TEMPORARY TABLE: ${SOURCETABLE} \n
    PORTABILITY DATABASE: ${DBPROD} \n PORTABILITY TABLE: ${PRODTABLE}  "
    touch .lupdate
    lastupdate="$(cat .lupdate)"
}

########################################################
# Check if the portability had already been done today #
########################################################


_check_update(){
    if [[ ${lastupdate} == $(date +%F) ]]; then
        _log "The database is updated (Last update was ${lastupdate})"
        exit 1
    fi
}

###########################################################################
# Check if the source data database already exist, and create if it didnt #
###########################################################################

_dbsource_check(){
    LIKEDBSOURCE="'${DBSOURCE}'"
    local DBSOURCEEXISTS="$(${SQL_LOCAL} -sse "show databases like ${LIKEDBSOURCE}")"

    _test_error "FAILED TO CHECK DB ${DBSOURCE} EXISTENCE, ACCES DENIED at $(hostname)"
    #Checking if the Database exists and create it if it didnt.
    if [ "${DBSOURCEEXISTS}" != "${DBSOURCE}" ] ; then
        _dbsource_create
    fi
}

###############################
# Create source data database #
###############################

_dbsource_create(){
    _log "Database ${DBSOURCE} not found at $(hostname) "
    ${SQL_LOCAL} -e "CREATE DATABASE ${DBSOURCE};"
    _test_error "FAILED TO CREATE DATABASE ${DBSOURCE} at $(hostname)"
    _log "Database ${DBSOURCE} created at $(hostname)"
}

#######################################################
# Create the source data table with the source format #
#######################################################

_sourcetb_create(){
    if  [[ ''$(${SQL_LOCAL} -D${DBSOURCE} -sse "select count(*) from ${SOURCETABLE};") == '' ]] ; then
        _log "Table ${SOURCETABLE} not found at $(hostname)"
        _log "Starting to create ${SOURCETABLE} table at $(hostname)"
        ${SQL_LOCAL} -D${DBSOURCE} -e "
        CREATE TABLE ${SOURCETABLE} (
            id bigint(32) NOT NULL,
            tn bigint(12) NOT NULL,
            rn1 varchar(6) NOT NULL,
            reciepient_sp varchar(6) NOT NULL,
            recipient_eot varchar(6) NOT NULL,
            activation_timestamp datetime NULL,
            lnp_type char(10) NULL,
            download_reason char(10) NULL,
            line_type char(10) NULL,
            new_cnl varchar(10) NULL,
            invoke_id varchar(32) NULL,
            PRIMARY KEY (id)
        );"
        _test_error " FAILED TO CREATE TABLE ${SOURCETABLE} at $(hostname)"
        _log "Table  ${SOURCETABLE} created at $(hostname)"
    fi
    _wipe_old_sourcetb_data
}

#######################################
# Wipe old data from the source table #
#######################################

_wipe_old_sourcetb_data(){
    _log "Starting to wipe outdated data"
    ${SQL_LOCAL} -D${DBSOURCE} -e "DELETE FROM ${SOURCETABLE}"
    _test_error "FAILED TO DELETE OUTDATED DATA(OLD ${SOURCETABLE}) AT $(hostname) "
    _log "Outdated data(old ${SOURCETABLE}) removed at $(hostname)"
}

#################################
# Download the source data file #
#################################

_sourcedb_download(){
    #(1) Get yesteday date (The full DB is updated late in the day, so to get the actual,
    # you need to get the one that was sent yesterday)
    _log "Starting to download full DB from ${DOWNLOAD_LINK} at $(hostname)"
    wget --user=${DOWNLOAD_USER} --password=${DOWNLOAD_PASS} ${DOWNLOAD_LINK}
    _test_error "FAILED TO DOWNLOAD FULL DB FROM ${DOWNLOAD_LINK} at $(hostname)"
    _log "Full DB downloaded from ${DOWNLOAD_LINK} at $(hostname)"
}

##############################
# Unzip the source data file #
##############################

_sourcedb_unzip(){
    _log "Start to unzip full DB (BDO_${YDATE}.bz2) at $(hostname)"
    bzip2 -d BDO_${YDATE}.bz2
    _test_error "FAILED TO UNZIP FULL DB (BDO_${YDATE}.bz2) at $(hostname)"
    _log "Full Portability file(BDO_${YDATE}.bz2) unziped at $(hostname)"
}

############################################################################################
# Add a "|" at the end of each line, so is possible to do the dump of the source data file #
############################################################################################

_sourcedb_awk(){
    _log "Starting to adequate BDO_${YDATE} file for import(${SQL_SECURE}/BDO_${YDATE}_bd) at $(hostname)"
    awk '{print $0"|"}' BDO_${YDATE} > ${SQL_SECURE}/BDO_${YDATE}_bd
    _log "BDO_${YDATE} file readequate to '${SQL_SECURE}/BDO_${YDATE}_bd' at $(hostname)"
    _test_error "AWK FAILED at BDO_${YDATE} AT $(hostname)"
}

####################################################
#  Populate source table with the source file data #
####################################################

_sourcetb_load(){
    _log "Starting to load Full DB at $(hostname)"
    ${SQL_LOCAL} -D${DBSOURCE} -e "
    LOAD DATA INFILE '${SQL_SECURE}/BDO_${YDATE}_bd'
    INTO TABLE ${SOURCETABLE}
    FIELDS TERMINATED BY  '|'
    LINES TERMINATED BY '\n';"
    _test_error "FAILED TO LOAD THE DOWNLOADED FILE DB at $(hostname)"
    _log "Full Portability loaded to ${SOURCETABLE} $(hostname)"
    _sourcetb_load_check
}

#####################################################
# Check if the source table was correctly populated #
#####################################################

_sourcetb_load_check(){
    WCFILE="$(wc -l < ${SQL_SECURE}/BDO_${YDATE}_bd | tr -d ' ')"
    COUNT_SOURCETABLE="$(${SQL_LOCAL} -D${DBSOURCE} -sse "select count(*) from ${SOURCETABLE};")"

    if [[ ${WCFILE} -ne ${COUNT_SOURCETABLE} ]] ; then
        _error "AMOUNT OF LINES at ${SOURCETABLE}(${COUNT_SOURCETABLE}) AND PORTABILITY FILE(${WCFILE} LINES)
                ARE DIFFERENT at $(hostname)"
    else
        _log "Amount of lines at ${SOURCETABLE} and portability file(BDO_${YDATE}_bd) verified(${WCFILE} lines) at $(hostname)"
    fi
}

#####################################################
# Check if the production database already exists.  #
# If it doesnt, create the function will create it  #
#####################################################

_dbprod_check(){
    LIKEDBPROD="'${DBPROD}'"
    DBPRODEXISTS="$(${SQL_LOCAL}  -e "show databases like ${LIKEDBPROD}")"

    _log "Verifying Database ${DBPROD} existance at $(hostname)"
    if [ "${DBPRODEXISTS}" != "${DBPROD}" ] ; then
        _log "Database ${DBPROD} not found at $(hostname)"
        _log "Creating production database ${DBPROD} at $(hostname)"
        ${SQL_LOCAL} -e "CREATE DATABASE ${DBPROD};"
        _test_error "FAILED TO CREATE ${DBPROD} DATABASE at $(hostname)"
        _log "${DBPROD} database created at $(hostname)"
    fi
}

################################
# Drop the old temporary table #
################################

_tmptb_drop_old(){
    _log "Dropping ${TMPTABLE} table if it exists $(hostname)"
    ${SQL_LOCAL} -e "drop table if exists ${DBPROD}.${TMPTABLE};"
    _test_error "FAILED TO DROP ${TMPTABLE} TABLE at $(hostname)"
    _log "${TMPTABLE} table dropped if it existed at $(hostname)"
}

###############################################
# Create the tempory table with AVCorp format #
###############################################

_tmptb_create(){
    _log "Creating ${TMPTABLE} table at $(hostname)"
    ${SQL_LOCAL} -e "
    create table
    ${DBPROD}.${TMPTABLE} (
        id int(64) not null auto_increment,
        numero bigint(20) not null,
        rn1 int(5) not null,
        data_janela datetime not null,
        acao int(1) default null,
        primary key (id),
        key idx_id (id),
        key idx_num (numero)
    ) engine = MyISAM charset = utf8;"
    _test_error "FAILED TO CREATE ${TMPTABLE} TABLE at $(hostname)"
    _log "${TMPTABLE} table created at $(hostname)"
}

########################################################
# Populate temporary table with the source tables data #
########################################################


_tmptb_insert(){
    _log "Populating ${TMPTABLE} table at $(hostname)"
    ${SQL_LOCAL} -e "
      insert into
        ${DBPROD}.${TMPTABLE} (numero, rn1, data_janela, acao)
        select
            tn as numero,
            rn1 as rn1,
            activation_timestamp as data_janela,
            1 as acao
        from
        (
            select
            *
            from
                ${DBSOURCE}.${SOURCETABLE}
        ) as v;"
    _test_error "FAILED TO POPULATE ${TMPTABLE} TABLE  at $(hostname)"
    _tmptb_insert_check
}

############################################################
# Check if the the temporary table was correctly populated #
############################################################

_tmptb_insert_check(){
    COUNT_TMPTABLE="$(${SQL_LOCAL} -D${DBPROD} -sse "select count(*) from ${TMPTABLE};")"
    COUNT_SOURCETABLE="$(${SQL_LOCAL} -D${DBSOURCE} -sse "select count(*) from ${SOURCETABLE};") "

    if [[ ${COUNT_SOURCETABLE} -ne ${COUNT_TMPTABLE} ]]; then
        _error "amount OF LINES at ${SOURCETABLE}(${COUNT_SOURCETABLE} LINES) AND ${TMPTABLE}(${COUNT_TMPTABLE} LINES)
               ARE DIFFERENT at $(hostname)"
    else
        _log "Amount of lines at ${SOURCETABLE} AND ${TMPTABLE} verified(${COUNT_SOURCETABLE}) at $(hostname)"
    fi
    _log "Population of ${TMPTABLE} table done at $(hostname)"
}

##############################################################################################################
# Check if the last insert of the new temporary is newer than the last insert of the actual production table #
# If the last insert of the production table is newer, it triggers an error                                  #
##############################################################################################################

_tmptb_last_insert_check(){
    last_insert_tmptb="$(${SQL_LOCAL} -sse  "select max(data_janela) from ${DBPROD}.${TMPTABLE}")"
    last_insert_prodtb="$(${SQL_LOCAL} -sse  "select max(data_janela) from ${DBPROD}.${PRODTABLE}")"
    LIKEPRODTABLE="'${PRODTABLE}'"
    TBPRODEXISTS="$(${SQL_LOCAL} -D${DBPROD} -e "show tables like ${LIKEPRODTABLE};")"
    if [ "${TBPRODEXISTS}" == "${PRODTABLE}"  ]; then
        last_insert="$(${SQL_LOCAL}  -sse "
        select
            case when vdates.new > vdates.old then '1' else '0' end
        from
            (
                select
                    vold.max_data_janela as old,
                    max(newp.data_janela) as new
                from
                    (
                        select
                            max(data_janela) as max_data_janela
                        from
                            ${DBPROD}.${PRODTABLE}
                    ) as vold,
                    ${DBPROD}.${TMPTABLE} newp
            )
            as vdates;")"

        if [[ ${last_insert} -eq "0" ]]; then
            _error "LAST UPDATED OF ${TMPTABLE} LINE SAME OR OLDER DATE THEN ${PRODTABLE} at $(hostname)"
        fi
    fi
}

################################################
# Transfer the portabily to the remote servers #
################################################

_remote_servers(){
    _check_remote_conf
    nserver="0"
    for DSTSERVER in "${DESTSERVER[@]}"
    do
        start_remote[${nserver}]=$(date +'%Y-%m-%d %H:%M:%S %z')
        SQL_REMOTE="${SQL_PATH} -s -N -u${DBUSERDST[${nserver}]} -p${DBPASSDST[${nserver}]} -h${DESTSERVER[${nserver}]} \
            -P${PORTDESTSERVER[${nserver}]}"

        _db_remote_check

        _tmptb_remote_dump

        _prodtb_remote_check

        _prodtb_remote_rename

        _oldprodtb_remote_remove

        end_remote[${nserver}]=$(date +'%Y-%m-%d %H:%M:%S %z')
    nserver="$((nserver+1))"
    done
}

########################################################
# Check if the remote configuration was done correctly #
########################################################

_check_remote_conf(){
    if [[ ${#DESTSERVER[@]} != ${#PORTDESTSERVER[@]}  \
        || ${#DESTSERVER[@]} != ${#DBPASSDST[@]}  \
        || ${#DESTSERVER[@]} != ${#DBUSERDST[@]} ]]; then
        _error "MISSING VARIABLE at ARRAY FROM  PORTABILITY.CONF FILE"
    fi
}

#######################################################################
# Check if the production databse already exists on the remote server #
#######################################################################

_db_remote_check(){
    LIKEDBPROD="'${DBPROD}'"
    DBSERVEREXISTS=''
    DBSERVEREXISTS="$(${SQL_REMOTE} -e "show databases like ${LIKEDBPROD}")"

    _test_error "FAILED TO CHECK DB at ${DESTSERVER[${nserver}]}, ACCESS DENIED at ${DESTSERVER[${nserver}]}"
    if [ "${DBSERVEREXISTS}" != "${DBPROD}"  ] ; then
        _db_remote_create
    fi
    last_insert_remote_prodtb[${nserver}]="$(${SQL_REMOTE} -sse  "select max(data_janela) from ${DBPROD}.${PRODTABLE};")"
    count_remote_old[${nserver}]="$(${SQL_REMOTE} -sse "select count(*) from ${DBPROD}.${PRODTABLE};")"
}

#######################################################
# Create the production database on the remote server #
#######################################################

_db_remote_create(){
    _log "Database ${DBPROD} not found at ${DESTSERVER[${nserver}]}"
    _log "Creating ${DBPROD} database at ${DESTSERVER[${nserver}]}"
    ${SQL_REMOTE} -e "CREATE DATABASE ${DBPROD};"
    _test_error "FAILED TO CREATE ${DBPROD} DATABASE at ${DESTSERVER[${nserver}]} "
    _log "Database ${DBPROD} created at ${DESTSERVER[${nserver}]}"

}

##########################################################################
# Dump data from the local temporary table to the remote temporary table #
##########################################################################

_tmptb_remote_dump(){
    _log "Sending ${TMPTABLE} table and loading it from $(hostname) to ${DESTSERVER[${nserver}]} "
    ${SQL_DUMP_LOCAL} ${DBPROD} ${TMPTABLE} \
        | ${SQL_REMOTE} ${DBPROD}
    _test_error "FAILED TO SEND ${TMPTABLE} TABLE from $(hostname) TO ${DESTSERVER[${nserver}]} "
    _log "${TMPTABLE} table sent sucessfully from $(hostname) to ${DESTSERVER[${nserver}]} "
    _tmptb_remote_dump_check
}

###########################################################
# Check if dump was done sucessfully on the remote server #
###########################################################

_tmptb_remote_dump_check(){
    COUNT_TMPTABLE="$(${SQL_LOCAL} -D${DBPROD} -sse "select count(*) from ${TMPTABLE};") "
    COUNT_TMPTABLE_REMOTE="$(${SQL_REMOTE} -D${DBPROD} -sse "select count(*) from ${TMPTABLE};")"

    if [[ ${COUNT_TMPTABLE} -ne ${COUNT_TMPTABLE_REMOTE} ]]; then
        _error "AMOUNT OF LINES at  $(hostname) ${TMPTABLE}(${COUNT_TMPTABLE} lines) AND
        ${DESTSERVER[${nserver}]} ${TMPTABLE}(${COUNT_TMPTABLE_REMOTE} lines)  ARE DIFFERENT"
    else
        _log "Amount of lines at local ${TMPTABLE} and ${DESTSERVER} ${TMPTABLE} verified (${COUNT_TMPTABLE} lines)."
    fi
}

####################################################################
# Check if the production table alredy exists on the remote server #
####################################################################

_prodtb_remote_check(){
    LIKEBACKUPTABLE="'${PRODTABLE}_${YDATE}'"
    BACKUPTBEXISTS="$(${SQL_REMOTE} -D${DBPROD} -e "show tables like ${LIKEBACKUPTABLE};")"

    _log "Check if there is a backup named as ${PRODTABLE}_${YDATE} at ${DESTSERVER[${nserver}]}."
    if [ "${BACKUPTBEXISTS}" == "${PRODTABLE}_${YDATE}" ]; then
        _prodtb_remote_backup_drop
    fi

    LIKEPRODTABLE="'${PRODTABLE}'"
    TBSERVEREXISTS="$(${SQL_REMOTE} -D${DBPROD} -e "show tables like ${LIKEPRODTABLE};")"

    _log "Checking if ${PRODTABLE} already exists at ${DESTSERVER[${nserver}]} "
    if [ "${TBSERVEREXISTS}" == "${PRODTABLE}"  ] ; then
        _prodtb_remote_backup
    fi
}
############################################################################
# Drop the "today" backup if it already exists at remote server            #
#(This function only run if it is the 2nd time the script is ran in a day) #
############################################################################

_prodtb_remote_backup_drop(){
    _log "Dropping actual backup ${PRODTABLE}_${YDATE} to create a new one at ${DESTSERVER[${nserver}]}."
    ${SQL_REMOTE} -e "drop table if exists ${DBPROD}.${PRODTABLE}_${YDATE};"
    _test_error "FAILED TO DROP BACKUP ${PRODTABLE}_${YDATE} at ${DESTSERVER[${nserver}]}"
    _log "Actual backup ${PRODTABLE}_${YDATE} dropped to create new one at ${DESTSERVER[${nserver}]}."
}

##################################################################
# Rename the production table adding yesterday date to its name, #
# becoming the backup file at remote server.                     #
##################################################################

_prodtb_remote_backup(){
    _log "Renaming old ${PRODTABLE} table at ${DESTSERVER[${nserver}]}"
    ${SQL_REMOTE} -e "rename table ${DBPROD}.${PRODTABLE} to ${DBPROD}.${PRODTABLE}_${YDATE};"
    _test_error "FAILED TO RENAME OLD ${PRODTABLE} TABLE at ${DESTSERVER[${nserver}]}"
    _log "Old ${PRODTABLE} table renamed to ${PRODTABLE}_${YDATE} at ${DESTSERVER[${nserver}]}"
}

#######################################################################
# Rename temporary table to the production table at the remote server #
#######################################################################

_prodtb_remote_rename(){
    _log "Renaming ${TMPTABLE} to  ${PRODTABLE} at ${DESTSERVER[${nserver}]}"
    ${SQL_REMOTE} -e "rename table ${DBPROD}.${TMPTABLE} to ${DBPROD}.${PRODTABLE};"
    _test_error "FAILED TO RENAME ${TMPTABLE} TABLE at ${DESTSERVER[${nserver}]}"
    _log "${TMPTABLE} table renamed to ${PRODTABLE} at ${DESTSERVER[${nserver}]}"
}

################################################################
# Drop the the backups created 2 days ago at the remote server #
################################################################

_oldprodtb_remote_remove(){
    ${SQL_REMOTE} -e "drop table if exists ${DBPROD}.${PRODTABLE}_${YYDATE}"
    _test_error "FAILED TO DROP 2 DAYS AGO TABLE at ${DESTSERVER[${nserver}]}"
    _log "Dropping Table from 2 days ago ${PRODTABLE} table at ${DESTSERVER[${nserver}]}"

    COUNT_TMPTABLE_REMOTES="${COUNT_TMPTABLE_REMOTES[@]} ${COUNT_TMPTABLE_REMOTE}"
}

###########################################################################################
# Rename the production table adding yesterday date to its name, becoming the backup file #
###########################################################################################
_prodtb_backup(){
    COUNT_PRODTABLE="$(${SQL_LOCAL} -D${DBPROD} -sse "select count(*) from ${PRODTABLE};")"
    LIKEBACKUPTABLE="'${PRODTABLE}_${YDATE}'"
    BACKUPTBEXISTS="$(${SQL_LOCAL} -D${DBPROD} -e "show tables like ${LIKEBACKUPTABLE};")"
    _log "  Check if there is a backup named as ${PRODTABLE}_${YDATE} at $(hostname)"
    if [ "${BACKUPTBEXISTS}" == "${PRODTABLE}_${YDATE}" ]; then
    _prodtb_backup_drop
    fi

    LIKEPRODTABLE="'${PRODTABLE}'"
    TBPRODEXISTS="$(${SQL_LOCAL} -D${DBPROD} -e "show tables like ${LIKEPRODTABLE};")"
    if [ "${TBPRODEXISTS}" == "${PRODTABLE}"  ]; then
        _log "Backing up old ${DBPROD}(Production) Table at $(hostname)"
        ${SQL_LOCAL} -e "rename table ${DBPROD}.${PRODTABLE} to ${DBPROD}.${PRODTABLE}_${YDATE};"
        _test_error "FAILED TO RENAME OLD ${PRODTABLE} TO ${PRODTABLE}_${YDATE} TABLE at $(hostname)"
        _log "Old ${PRODTABLE} Table renamed to ${PRODTABLE}_${YDATE}) at $(hostname)"
    fi
}

#############################################################################
#  Drop the "today" backup if it already exists                             #
# (This function only run if it is the 2nd time the script is ran in a day) #
#############################################################################
_prodtb_backup_drop(){
    _log "Dropping actual backup t${PRODTABLE}_${YDATE} o create a new one at ${hostname}."
    ${SQL_LOCAL} -e "drop table if exists ${DBPROD}.${PRODTABLE}_${YDATE};"
    _test_error "FAILED TO DROP BACKUP ${PRODTABLE}_${YDATE} at $(hostname)"
    _log "Actual backup ${PRODTABLE}_${YDATE} dropped to create new one at $(hostname)"
}

##################################################
# Rename temporary table to the production table #
##################################################
_prodtb_rename(){
    _log "Renaming  ${TMPTABLE} to ${PRODTABLE} at $(hostname)"
    ${SQL_LOCAL} -e "rename table ${DBPROD}.${TMPTABLE} to ${DBPROD}.${PRODTABLE};"
    _test_error "FAILED TO RENAME ${TMPTABLE} to ${PRODTABLE} at $(hostname)"
    _log "Table ${TMPTABLE} renamed to ${PRODTABLE} at $(hostname)"
}

###########################################
# Drop the the backups created 2 days ago #
###########################################
_drop_old_backups(){
    _log "Dropping ${PRODTABLE}${YYDATE} Table from 2 days ago at $(hostname)"
    ${SQL_LOCAL} -e "drop table if exists ${DBPROD}.${PRODTABLE}_${YYDATE}"
    _test_error "FAILED TO DROP 2 DAYS AGO TABLE(${PRODTABLE}_${YYDATE}) at $(hostname)"
    _log "Portables Table from 2 days ago table(${PRODTABLE}_${YYDATE}) dropped at $(hostname)"
}


##################################################
# Send a report after the full run of the script #
##################################################

_final_report(){
    date +%F > .lupdate
    _log "Portability.sh sucessfully finished"

    endtime="$(date +%s)"

    if [[ "$(uname)" == "Linux" ]]; then
        runtime="$(date -d@$((endtime-starttime)) -u +%H:%M:%S)"
    elif [[ "$(uname)" == "FreeBSD" ]]; then
        runtime="$(date -r$((endtime-starttime)) -u +%H:%M:%S)"
    fi

    msg="REPORT:

    Old portability:
    Count_old_portados: ${COUNT_PRODTABLE}
    Date_from_last_insert: ${last_insert_prodtb}

    New Portability:
    Start: ${start}
    Date_from_last_insert: ${last_insert_tmptb}
    Count_downloaded_file: ${WCFILE}
    Count_table_loaded_file: ${COUNT_SOURCETABLE}
    Count_production_table: ${COUNT_TMPTABLE}
    End: $(date +'%Y-%m-%d %H:%M:%S %z')"

    mail_msg="REPORT:      \n
    Old portability: \n
    Count_old_produciton_table: ${COUNT_PRODTABLE} \n
    Date_from_last_insert: ${last_insert_prodtb} \n
    New Portability: \n
    Start_time: ${start} \n
    Date_from_last_insert: ${last_insert_tmptb} \n
    Count_downloaded_file: ${WCFILE}          \n
    Count_table_loaded_file: ${COUNT_SOURCETABLE}  \n
    Count_production_table: ${COUNT_TMPTABLE} \n
    End_time: $(date +'%Y-%m-%d %H:%M:%S %z') \n"


    i="0"
    for remote in ${DESTSERVER[@]}; do
        msg="${msg}

    Remote[${remote}]:
    Old Portability:
    Count_old_production_table_remote[${remote}]: ${count_remote_old[$i]}
    Last_insert_old_production_table_remote[${remote}]: ${last_insert_remote_prodtb[$i]}
    New Portability:
    Start_time_remote[${remote}]: ${start_remote[$i]}
    Count_production_table_remote[${remote}]: ${COUNT_TMPTABLE_REMOTES[$i]}
    End_time[${remote}]: ${end_remote[$i]}"

        mail_msg="${mail_msg} \n
    Remote: \n
    Old Portability: \n
    Count_old_production_table_remote[${remote}]: ${count_remote_old[$i]}\n
    Last_insert_old_production_table_remote[${remote}]: ${last_insert_remote_prodtb[$i]} \n
    New Portability: \n
    Start_time_remote[${remote}]: ${start_remote[$i]} \n
    Count_production_table_remote[${remote}]: ${COUNT_TMPTABLE_REMOTES[$i]} \n
    End_time[${remote}]: ${end_remote[$i]} \n"

        i="$((i+1))"
    done

    if [[ -n ${runtime} ]]; then
        msg="${msg}

    Full runtime: ${runtime}"
        mail_msg="${mail_msg} \n \n
    Full runtime: ${runtime} \n"
    fi


    SENDOPTION="REPORT"
    _send_telegram_msg "${msg}"

    _send_mail_msg "${mail_msg}"
}

##################################################
# Help command to display the script run options #
##################################################

_help(){
    echo -e "Usage: bash ./portability.sh [OPTIONS]
Portability.sh is a script made to update AVCorp potability databases.
For script and local server configuration, edit portability.conf file.
For remote servers configuration, edit remote-servers.conf
To run full script run bash portability.sh -f

Possible commands:
  -h (Help) - To display the portability manual
  -c (Clean) - To clear old downloaded portability files and drop old temporary table.
  -d (Download) - To download and readequate source portability file.
     (The unmodified file is sed in portability directory and the readequated file on your SQL secure directory)
  -s (Source) - Create source table based on the source portability and load its downloaded file.
     (The download option need to be already ran before this)
  -t (Temporary) - To create AVCorp format table and load data from the temporary table.
     (To run this, the temporary table should be alredy populated)
  -r (Remote) - To send AVCorp temporary file to remote server and replace the production table.
  -p (Production) - To backup the production table and rename AVCorp temporary table to be the production table.
  -f (Full) - Run the full portability.sh script.
              It will run every command above and send a report at the final, by telegram and email."
    exit
}

#######################################################################
# Clear old downloaded portability files and drop old temporary table #
#######################################################################

_clean(){
    _basic_conf
    _remove_source_files
    _wipe_old_sourcetb_data
}

###################################################
# Download and readequate source portability file #
###################################################

_download(){
    _basic_conf
    _remove_source_files
    _sourcedb_download
    _sourcedb_unzip
    _sourcedb_awk
}

####################################################################################
# Create source table based on the source portability and load its downloaded file #
####################################################################################

_source(){
    _basic_conf
    _dbsource_check
    _sourcetb_create
    dw="$(ls ${SQL_SECURE} | grep BDO_${YDATE}_bd)"
    if [[ -n ${dw} ]]; then
        _sourcetb_load
    else
        _error "DATABASE FILE NOT FOUND (TO RUN THIS FUNCTION, THE DATABASE FILE NEED TO BE ALREADY DOWNLOADED)"
    fi
}
########################################################################
# To create AVCorp format table and load data from the temporary table #
########################################################################

_temporary(){
    _basic_conf
    _dbprod_check
    _tmptb_drop_old
    _dbsource_check
    _tmptb_create
    _tmptb_insert
    _tmptb_last_insert_check
}

################################################################################
# Send AVCorp temporary file to remote server and replace the production table #
################################################################################

_remote(){
    _basic_conf
    _check_update
    _remote_servers
}

#############################################################################################
# Backup the production table and rename AVCorp temporary table to be the production table. #
#############################################################################################

_production(){
    _basic_conf
    _check_update
    _tmptb_last_insert_check
    _prodtb_backup
    _prodtb_rename
    _drop_old_backups
}

###############################################################################################
# Run the full portability.sh script, it will:                                                #
# - Clear old downloaded portability files and drop old temporary table                       #
# - Download and readequate source portability file                                           #
# - Create source table based on the source portability and load its downloaded file          #
# - Backup the production table and rename AVCorp temporary table to be the production table. #
# - Send a report to telegram and email addresses                                             #
###############################################################################################

_full(){
    _basic_conf
    _check_update
    _remove_source_files
    _dbsource_check
    _sourcetb_create
    _sourcedb_download
    _sourcedb_unzip
    _sourcedb_awk
    _sourcetb_load
    _dbprod_check
    _tmptb_drop_old
    _tmptb_create
    _tmptb_insert
    _tmptb_last_insert_check
    _remote_servers
    _prodtb_backup
    _prodtb_rename
    _drop_old_backups
    _final_report
    _remove_source_files
}

_main(){
    arg=0
    while getopts 'hcdstrpf' c; do
        case $c in
            c) _clean;;
            d) _download ;;
            s) _source ;;
            t) _temporary;;
            r) _remote;;
            p) _production;;
            f) _full;;
            ?) _help;;
        esac
        arg=1
    done
    if [[ ${arg} == 0 ]];then
    _help
    fi
}


_main $@
