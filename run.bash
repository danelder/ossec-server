#!/bin/bash

#
# OSSEC container bootstrap. See the README for information of the environment
# variables expected by this script.
#
source /data_dirs.env
FIRST_TIME_INSTALLATION=false
DATA_PATH=/var/ossec/data

for ossecdir in "${DATA_DIRS[@]}"; do
  if [ ! -e "${DATA_PATH}/${ossecdir}" ]
  then
    echo "Installing ${ossecdir}"
    cp -pr /var/ossec/${ossecdir}-template ${DATA_PATH}/${ossecdir}
    FIRST_TIME_INSTALLATION=true
  fi
done

#
# Check for the process_list file. If this file is missing, it doesn't
# count as a first time installation
#
touch ${DATA_PATH}/process_list
chgrp ossec ${DATA_PATH}/process_list
chmod g+rw ${DATA_PATH}/process_list

#
# At a minimum there should be 6 services running, ossec-execd, ossec-analysisd, ossec-logcollector, ossec-remoted, ossec-syscheckd, and ossec-monitord
#
SERVICES=6


#
# If this is a first time installation, then do the  
# special configuration steps.
#
AUTO_ENROLLMENT_ENABLED=${AUTO_ENROLLMENT_ENABLED:-true}
WEB_ENABLED=${WEB_ENABLED:-true}
#
# Support SMTP, if configured
#
SMTP_ENABLED_DEFAULT=false
if [ -n "$ALERTS_TO_EMAIL" ]
then
  SMTP_ENABLED_DEFAULT=true
  ((SERVICES+=1))
fi
SMTP_ENABLED=${SMTP_ENABLED:-$SMTP_ENABLED_DEFAULT}

if [ $FIRST_TIME_INSTALLATION == true ]
then 
  
  #
  # Support auto-enrollment if configured
  #
  if [ $AUTO_ENROLLMENT_ENABLED == true ]
  then
    if [ ! -e ${DATA_PATH}/etc/sslmanager.key ]
    then
      echo "Creating ossec-authd key and cert"
      openssl genrsa -out ${DATA_PATH}/etc/sslmanager.key 4096
      openssl req -new -x509 -key ${DATA_PATH}/etc/sslmanager.key\
        -out ${DATA_PATH}/etc/sslmanager.cert -days 3650\
        -subj /CN=${HOSTNAME}/
    fi
  fi

  if [ $SMTP_ENABLED == true ]
  then
    if [[ -z "$SMTP_RELAY_HOST" || -z "$ALERTS_TO_EMAIL" ]]
    then
      echo "Unable to configure SMTP, SMTP_RELAY_HOST or ALERTS_TO_EMAIL not defined"
      SMTP_ENABLED=false
    else
      
      ALERTS_FROM_EMAIL=${ALERTS_FROM_EMAIL:-ossec_alerts@$HOSTNAME}
      sed -i 's/<email_notification>.*<\/email_notification>/<email_notification>yes</email_notification>/' /var/ossec/etc/ossec.conf 
      sed -i "s/<email_from>.*<\/email_from>/<email_from>${ALERTS_FROM_EMAIL}<\/email_from>/" /var/ossec/etc/ossec.conf 
      sed -i "s/<email_to>.*<\/email_to>/<email_to>${ALERTS_TO_EMAIL}<\/email_to>/" /var/ossec/etc/ossec.conf 
      sed -i "s/<smtp_server>.*<\/smtp_server>/<smtp_server>${SMTP_RELAY_HOST}<\/smtp_server>/" /var/ossec/etc/ossec.conf 
    fi
  fi
  
  if [ $SMTP_ENABLED == false ]
  then
    sed -i 's/<email_notification>.*<\/email_notification>/<email_notification>no<\/email_notification>/' /var/ossec/etc/ossec.conf 
  fi

  #
  # Support SYSLOG forwarding, if configured
  #
  SYSLOG_FORWADING_ENABLED=${SYSLOG_FORWADING_ENABLED:-false}
  if [ $SYSLOG_FORWADING_ENABLED == true ]
  then
    if [ -z "$SYSLOG_FORWARDING_SERVER_IP" ]
    then
      echo "Cannot setup sylog forwarding because SYSLOG_FORWARDING_SERVER_IP is not defined"
    else
      SYSLOG_FORWARDING_SERVER_PORT=${SYSLOG_FORWARDING_SERVER_PORT:-514}
      SYSLOG_FORWARDING_FORMAT=${SYSLOG_FORWARDING_FORMAT:-default}
      SYSLOG_XML_SNIPPET="\
  <syslog_output>\n\
    <server>${SYSLOG_FORWARDING_SERVER_IP}</server>\n\
    <port>${SYSLOG_FORWARDING_SERVER_PORT}</port>\n\
    <format>${SYSLOG_FORWARDING_FORMAT}</format>\n\
  </syslog_output>";

      cat /var/ossec/etc/ossec.conf |\
        perl -pe "s,<ossec_config>,<ossec_config>\n${SYSLOG_XML_SNIPPET}\n," \
        > /var/ossec/etc/ossec.conf-new
      mv -f /var/ossec/etc/ossec.conf-new /var/ossec/etc/ossec.conf
      chgrp ossec /var/ossec/etc/ossec.conf
      /var/ossec/bin/ossec-control enable client-syslog
    fi
  fi
  
  #
  # Setup htpasswd access to web frontend if configured
  #
  if [ $WEB_ENABLED == true ]
  then
    if [ -z "$WEB_USER" -o -z "$WEB_PASSWORD" ]
    then
      echo "Missing WEB_USER or WEB_PASSWORD, will use insecure default of admin/admin for web access"
      /usr/bin/htpasswd -bc /var/ossec/data/.htpasswd admin admin
    else
      /usr/bin/htpasswd -bc /var/ossec/data/.htpasswd "$WEB_USER" "$WEB_PASSWORD"
    fi
  fi
fi

function ossec_shutdown(){
  /var/ossec/bin/ossec-control stop;
  if [ $AUTO_ENROLLMENT_ENABLED == true ]
  then
     kill $AUTHD_PID
  fi

  if [ $WEB_ENABLED == true ]
  then
     /etc/init.d/httpd stop
  fi
}

# Trap exit signals and do a proper shutdown
trap "ossec_shutdown; exit" SIGINT SIGTERM

#
# Startup the services
#
chmod -R g+rw ${DATA_PATH}/logs/ ${DATA_PATH}/stats/ ${DATA_PATH}/queue/ ${DATA_PATH}/etc/client.keys
/var/ossec/bin/ossec-control start
if [ $WEB_ENABLED == true ]
then
  echo "Setting htpasswd access..."
  cp /var/ossec/data/.htpasswd /usr/share/ossec-wui/.htpasswd
  echo "Starting OSSEC web frontend..."
  /etc/init.d/httpd start
fi
if [ $AUTO_ENROLLMENT_ENABLED == true ]
then
  echo "Starting ossec-authd..."
  /var/ossec/bin/ossec-authd -p 1515 -g ossec $AUTHD_OPTIONS >/dev/null 2>&1 &
  AUTHD_PID=$!
  ((SERVICES+=1))
fi
sleep 15 # give ossec a reasonable amount of time to start before checking status
LAST_OK_DATE=`date +%s`

#
# Watch the service in a while loop, exit if the service exits
#

while true
do
  RUNNING=`ps awwwx | grep bin/ossec | grep -v grep | wc -l`
  if (( $RUNNING != $SERVICES ))
  then
    CUR_TIME=`date +%s`
    # Allow ossec to not run return an ok status for up to 15 seconds 
    # before worring.
    if (( (CUR_TIME - LAST_OK_DATE) > 15 ))
    then
      echo "ossec not properly running! exiting..."
      ossec_shutdown
      exit 1
    fi
  else
    LAST_OK_DATE=`date +%s`
  fi
  sleep 1
done
