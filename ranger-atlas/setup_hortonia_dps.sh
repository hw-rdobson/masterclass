#!/usr/bin/env bash
# Launch Centos 7 Vm 
# Then run:
# curl -sSL https://gist.githubusercontent.com/wcbdata/03a9a88a8f12d34f7bca56b120d8578d/raw | sudo -E sh  

########################################################################
########################################################################
## variables

export HOME=${HOME:-/root}
export TERM=xterm

#overridable vars
export stack=${stack:-hdp}    #cluster name
export ambari_pass=${ambari_pass:-admin}  #ambari password
export ambari_services=${ambari_services:-HBASE HDFS MAPREDUCE2 PIG YARN HIVE ZOOKEEPER SLIDER AMBARI_INFRA TEZ RANGER ATLAS KAFKA SPARK2 ZEPPELIN KNOX BEACON DPPROFILER}   #HDP services
export ambari_stack_version=${ambari_stack_version:-2.6}  #HDP Version
export host_count=${host_count:-1}      #number of nodes, defaults to 1
export enable_hive_acid=${enable_hive_acid:-true}   #enable Hive ACID?
export enable_kerberos=${enable_kerberos:-true}
export kdc_realm=${kdc_realm:-HWX.COM}      #KDC realm
export ambari_version="${ambari_version:-2.6.2.0}"   #Need Ambari 2.6.0+ to avoid Zeppelin BUG-92211

#Database passwords
export db_password=${db_password:-StrongPassword}
export hive_db_password=${hive_db_password:-H!veRox} #using default user hive on existing MariaDB database
export beacon_db_password=${beacon_db_password:-8eaconRox} #using default user beacon on existing MariaDB database

#Mpacks to add
export dss_url="http://s3.amazonaws.com/dev.hortonworks.com/DSS/centos7/1.x/BUILDS/1.1.0.0-125"
export dss_mpack_url="${dss_url}/tars/dataplane_profilers/dpprofiler-ambari-mpack-1.0.0.1.1.0.0-125.tar.gz"
export dss_repo="${dss_url}/dssbn.repo"

export dlm_url="http://s3.amazonaws.com/dev.hortonworks.com/DLM/centos7/1.x/BUILDS/1.1.0.0-185"
export dlm_mpack_url="${dlm_url}/tars/beacon/beacon-ambari-mpack-1.1.0.0-185.tar.gz"
export dlm_repo="${dlm_mpack_url}/dlmbn.repo"

#Variables for DSS
export dss_spnego_secret=${dss_spnego_secret:-some$ecretThisIs}
export dss_db_pass=${dss_db_pass:-H@doob} #using default user profileragent on existing MariaDB database

#LDAP Setup Variables
export LDAP_BASE="dc=hortonworks,dc=com"
export LDAP_ACCOUNTS_DN="ou=users,${LDAP_BASE}"
export LDAP_USER_GROUP="cn=Hadoop Users,ou=Group,dc=hortonworks,dc=com"
export LDAP_ADMIN_GROUP="cn=Hadoop Admins,ou=Group,dc=hortonworks,dc=com"
export LDAP_BIND_DN="cn=ldapadmin,dc=hortonworks,dc=com"
export LDAPPASS="h0rtonworks"
export LDAP_OPTIONS="-h dps-core2.field.hortonworks.com -p 389"
export USER_CLEARTEXT_PASS="BadPass#1" #Default for all demo users


#internal vars
export ambari_password="${ambari_pass}"
export cluster_name=${stack}
export recommendation_strategy="ALWAYS_APPLY_DONT_OVERRIDE_CUSTOM_VALUES"
export install_ambari_server=true
export deploy=true

export host=$(hostname -f)
export ambari_host=$(hostname -f)
## overrides
#export ambari_stack_version=2.6
#export ambari_repo=""

export install_ambari_server ambari_pass host_count ambari_services
export ambari_password cluster_name recommendation_strategy


########################################################################
########################################################################
##
cd

yum makecache fast
# sudo yum localinstall -y https://dev.mysql.com/get/mysql57-community-release-el7-8.noarch.rpm
# yum -y -q install git epel-release ntp screen mysql-community-server mysql-connector-java postgresql-jdbc jq python-argparse python-configobj nc ack

#Local repo for MariaDB 10.2.x - tested version

cat << EOF > /etc/yum.repos.d/MariaDB.repo
# MariaDB 10.2 CentOS repository list - created 2018-06-13 14:24 UTC
# http://downloads.mariadb.org/mariadb/repositories/
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.2/centos7-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF

#Package installs
yum -y -q install git epel-release ntp screen MariaDB-server MariaDB-client MariaDB-shared MariaDB-common mysql-connector-java postgresql-jdbc jq python-argparse python-configobj nc ack

#Script installs
curl -sSL -o add_user.sh https://gist.github.com/wcbdata/e138530642575e309c18d3f90e1938b6/raw
chmod gou+x add_user.sh

#Example LDAP add user:
#./add_user.sh -n admintest -c admintest -s Test -e admintest -m admintest@hortonworks.com -a

################################
# MySQL/MariaDB Setup using mysql sytntax
echo Database setup...
# Disable the services that conflict with the Ambari "MySQL Server" component startup
sudo systemctl disable mariadb.service
sudo systemctl disable mysqld.service
sudo systemctl enable mysql
sudo service mysql start # This syntax is required for Ambari to be able to start and stop the "MySQL Server" component 

#extract system generated Mysql password
#oldpass=$( grep 'temporary.*root@localhost' /var/log/mysqld.log | tail -n 1 | sed 's/.*root@localhost: //' )
#create sql file that
# 1. reset Mysql password to temp value and create druid/superset/registry/streamline schemas and users
# 2. sets passwords for druid/superset/registry/streamline users to ${db_password}
#TODO: update script to handle multiple hostnames, host-specific MySQL privs
cat << EOF > mysql-setup.sql
#ALTER USER 'root'@'localhost' IDENTIFIED BY 'Secur1ty!'; 
SET PASSWORD = PASSWORD('Secur1ty!');
#uninstall plugin validate_password; #only needed on MySQL
#Set global defaults for storage
SET storage_engine = INNODB;
SET GLOBAL innodb_file_format = BARRACUDA;
SET GLOBAL innodb_large_prefix = ON;
SET GLOBAL innodb_default_row_format = DYNAMIC;
#Create user and database for profiler
CREATE DATABASE profileragent DEFAULT CHARACTER SET latin1; 
CREATE USER 'profileragent'@'%' IDENTIFIED BY '${dss_db_pass}'; 
GRANT ALL PRIVILEGES ON profileragent.* TO 'profileragent'@'%' WITH GRANT OPTION ; 
CREATE USER 'profileragent'@'${host}' IDENTIFIED BY '${dss_db_pass}'; 
GRANT ALL PRIVILEGES ON profileragent.* TO 'profileragent'@'${host}' WITH GRANT OPTION ; 
#Create user and database for Hive (needed because we are already running a MySQL instance)
CREATE DATABASE hive DEFAULT CHARACTER SET utf8; 
CREATE USER 'hive'@'%' IDENTIFIED BY '${hive_db_password}'; 
GRANT ALL PRIVILEGES ON hive.* TO 'hive'@'%' WITH GRANT OPTION ; 
CREATE USER 'hive'@'${host}' IDENTIFIED BY '${hive_db_password}'; 
GRANT ALL PRIVILEGES ON hive.* TO 'profileragent'@'${host}' WITH GRANT OPTION ; 
#Create user and database for Beacon (needed because we are already running a MySQL instance)
CREATE DATABASE beacon DEFAULT CHARACTER SET utf8; 
CREATE USER 'beacon'@'%' IDENTIFIED BY '${beacon_db_password}'; 
GRANT ALL PRIVILEGES ON beacon.* TO 'beacon'@'%' WITH GRANT OPTION ; 
CREATE USER 'beacon'@'${host}' IDENTIFIED BY '${beacon_db_password}'; 
GRANT ALL PRIVILEGES ON beacon.* TO 'beacon'@'${host}' WITH GRANT OPTION ; 
commit; 
FLUSH PRIVILEGES;
EOF

#Make sure mysql (MariaDB) service uis running
while ! service mysql status; 
  do 
    echo "Waiting for mysql service ..."; 
    echo " If taking too long, use <service mysql start> from another ssh session";
    echo " to start or troubleshoot.";
    sleep 10;
  done

#execute sql file
#mysql -h localhost -u root -p"$oldpass" --connect-expired-password < mysql-setup.sql
mysql -h localhost -u root < mysql-setup.sql
#change Mysql password to ${db_password}
mysqladmin -u root -p'Secur1ty!' password ${db_password}
#test password and confirm dbs created
mysql -u root -p${db_password} -e 'show databases;'

#Set my.cnf settings to allow long indexes (innodb/barracuda/large_prefix/row_format)
#Required for MariaDB 10.1.x, may not be needed for 10.2.x
# sed -i '/^\[server\]/a\innodb_default_row_format = DYNAMIC' /etc/my.cnf.d/server.cnf
# sed -i '/^\[server\]/a\innodb_large_prefix = ON' /etc/my.cnf.d/server.cnf
# sed -i '/^\[server\]/a\innodb_file_format = BARRACUDA' /etc/my.cnf.d/server.cnf


###################################
echo Installing Ambari ...
curl -sSL https://raw.githubusercontent.com/seanorama/ambari-bootstrap/master/extras/deploy/install-ambari-bootstrap.sh | bash


########################################################################
########################################################################
## tutorial users

echo "Installing Hortonia Bank scripts ..."

#download hortonia scripts
cd /tmp
git clone https://github.com/abajwa-hw/masterclass

cd /tmp/masterclass/ranger-atlas/HortoniaMunichSetup
chmod +x *.sh
./04-create-os-users.sh

#also need anonymous user for kafka Ranger policy and dpprofiler for DSS
useradd ANONYMOUS
useradd dpprofiler


########################################################################
########################################################################
##

#install MySql community rpm
#sudo rpm -Uvh http://dev.mysql.com/get/mysql-community-release-el7-5.noarch.rpm

#install Ambari
echo "running prep-hosts.sh ..."
~/ambari-bootstrap/extras/deploy/prep-hosts.sh
echo "running ambari-bootstrap.sh ..."
~/ambari-bootstrap/ambari-bootstrap.sh

## Ambari Server specific tasks
if [ "${install_ambari_server}" = "true" ]; then

    sleep 30

#    curl -v -k -u admin:admin -H "X-Requested-By:ambari" -X POST http://localhost:8080/api/v1/version_definitions -d @- <<EOF
#{  "VersionDefinition": {   "version_url": "${hdp_vdf}" } }
#EOF

    ## add admin user to postgres for other services, such as Ranger
    cd /tmp
    sudo -u postgres createuser -U postgres -d -e -E -l -r -s admin
    sudo -u postgres psql -c "ALTER USER admin PASSWORD 'BadPass#1'";
    printf "\nhost\tall\tall\t0.0.0.0/0\tmd5\n" >> /var/lib/pgsql/data/pg_hba.conf
    #systemctl restart postgresql
    service postgresql restart

    ## bug workaround:
    sed -i "s/\(^    total_sinks_count = \)0$/\11/" /var/lib/ambari-server/resources/stacks/HDP/2.0.6/services/stack_advisor.py


    #Configure beacon mpack and install

    echo "Installing beacon mpack..."
    cd /tmp
    wget ${dlm_mpack_url}
    tar -xvzf beacon-ambari-mpack-*.tar.gz
    cp beacon-ambari-mpack-*/addon-services/BEACON/1.1.0/repos/repoinfo.xml ./repoinfo.xml.bak

    path=$(ls /tmp/beacon-ambari-mpack-*/addon-services/BEACON/1.1.0/repos/repoinfo.xml)
    cat << EOF > ${path}
    <reposinfo>
        <latest>http://s3.amazonaws.com/dev.hortonworks.com/DLM/dlm_urlinfo.json</latest>
        <os family="redhat7">
            <repo>
                <baseurl>${dlm_url}</baseurl>
                <repoid>DLM-1.1</repoid>
                <reponame>DLM</reponame>
            </repo>
        </os>
    </reposinfo>
EOF

    cat beacon-ambari-mpack-*/addon-services/BEACON/1.1.0/repos/repoinfo.xml
    sleep 30
    tar -zcvf beacon-ambari-mpack.tar.gz beacon-ambari-mpack-*
    sudo ambari-server install-mpack --verbose --mpack=/tmp/beacon-ambari-mpack.tar.gz

    
    sleep 5

    #Configure profiler mpack and install
    
    echo "Installing profiler mpack..."
    
    cd /tmp
    wget ${dss_mpack_url}
    tar -xvzf dpprofiler-ambari-mpack-*.tar.gz
    cp dpprofiler-ambari-mpack-*/addon-services/DPPROFILER/1.0.0/repos/repoinfo.xml ./repoinfo.xml.bak

    path=$(ls /tmp/dpprofiler-ambari-mpack-*/addon-services/DPPROFILER/1.0.0/repos/repoinfo.xml)
    cat << EOF > ${path}
    <reposinfo>
        <latest>http://s3.amazonaws.com/dev.hortonworks.com/DLM/dss_urlinfo.json</latest>
        <os family="redhat7">
            <repo>
                <baseurl>${dss_url}</baseurl>
                <repoid>DSS-1.0</repoid>
                <reponame>DSS</reponame>
            </repo>
        </os>
    </reposinfo>
EOF

    cat dpprofiler-ambari-mpack-*/addon-services/DPPROFILER/1.0.0/repos/repoinfo.xml
    sleep 30
    tar -zcvf dpprofiler-ambari-mpack.tar.gz dpprofiler-ambari-mpack-*
    sudo ambari-server install-mpack --verbose --mpack=/tmp/dpprofiler-ambari-mpack.tar.gz


    bash -c "nohup ambari-server restart" || true

    wget ${dss_repo} -P /etc/yum.repos.d/ 
    wget ${dlm_repo} -P /etc/yum.repos.d/ 
    
    ambari_pass=admin source ~/ambari-bootstrap/extras/ambari_functions.sh
    #until [ $(ambari_pass=BadPass#1 ${ambari_curl}/hosts -o /dev/null -w "%{http_code}") -eq "200" ]; do
    #    sleep 1
    #done

    echo "Checking to make sure Ambari is up before setting up drivers ..."

    while ! echo exit | nc localhost 8080; do echo "waiting for Ambari to come up..."; sleep 10; done
    sleep 10
    ambari_change_pass admin admin ${ambari_pass}

    yum -y install postgresql-jdbc
    ambari-server setup --jdbc-db=postgres --jdbc-driver=/usr/share/java/postgresql-jdbc.jar
    ambari-server setup --jdbc-db=mysql --jdbc-driver=/usr/share/java/mysql-connector-java.jar

    cd ~/ambari-bootstrap/deploy


	if [ "${enable_hive_acid}" = true  ]; then
		acid_hive_env="\"hive-env\": { \"hive_txn_acid\": \"on\" }"

		acid_hive_site="\"hive.support.concurrency\": \"true\","
		acid_hive_site+="\"hive.compactor.initiator.on\": \"true\","
		acid_hive_site+="\"hive.compactor.worker.threads\": \"1\","
		acid_hive_site+="\"hive.enforce.bucketing\": \"true\","
		acid_hive_site+="\"hive.exec.dynamic.partition.mode\": \"nonstrict\","
		acid_hive_site+="\"hive.txn.manager\": \"org.apache.hadoop.hive.ql.lockmgr.DbTxnManager\","
	fi

        ## various configuration changes for demo environments, and fixes to defaults
cat << EOF > configuration-custom.json
{
  "configurations" : {
    "core-site": {
        "hadoop.proxyuser.livy.groups": "*",
        "hadoop.proxyuser.livy.hosts": "*",
        "hadoop.proxyuser.knox.groups": "*",
        "hadoop.proxyuser.knox.hosts": "*",
        "hadoop.proxyuser.root.users": "admin",
        "fs.trash.interval": "4320"
    },
    "beacon-env": {
        "beacon_database" : "Existing MySQL / MariaDB Database",
	"beacon_store_url" : "jdbc:mysql://${host}/beacon",
        "beacon_store_user" : "beacon",
        "beacon_store_validate_connection" : "false",
	"beacon_store_db_name" : "beacon",
	"beacon_store_password" : "${beacon_db_password}",
	"beacon_store_driver" : "com.mysql.jdbc.Driver"
    },
    "dpprofiler-config": {
        "dpprofiler.db.database" : "profileragent",
        "dpprofiler.db.driver" : "com.mysql.jdbc.Driver",
        "dpprofiler.db.host" : "${host}",
        "dpprofiler.db.jdbc.url" : "jdbc:mysql://${host}:3306/profileragent?autoreconnect=true",
        "dpprofiler.db.password" : "${dss_db_pass}",
        "dpprofiler.db.slick.driver" : "slick.driver.MySQLDriver$",
        "dpprofiler.db.type" : "mysql",
        "dpprofiler.db.user" : "profileragent",
	"dpprofiler.spnego.signature.secret" : "${dss_spnego_secret}",
	"livy.session.config" : "\n            session {\n                lifetime {\n                    minutes = 2880\n                    requests = 500\n                }\n                max.errors = 40\n                starting.message = \"java.lang.IllegalStateException: Session is in state starting\"\n                dead.message = \"java.lang.IllegalStateException: Session is in state dead\"\n                config {\n                    read {\n                        name = \"dpprofiler-read\"\n                         heartbeatTimeoutInSecond = 172800\n                         timeoutInSeconds = 90\n                         driverMemory = \"1G\"\n                         executorMemory = \"1G\"\n                         numExecutors = 1\n                        executorCores = 1\n                     }\n                     write {\n                        name = \"dpprofiler-write\"\n                        heartbeatTimeoutInSecond = 172800\n                        timeoutInSeconds = 90\n                        driverMemory = \"1G\"\n                        executorMemory = \"1G\"\n                        numExecutors = 1\n                        executorCores = 1\n                     }\n                }\n            }"
    },
    "hdfs-site": {
      "dfs.namenode.safemode.threshold-pct": "0.99"
    },
    "livy2-conf": {
      "livy.superusers" : "zeppelin-${stack},dpprofiler-${stack}"
    },
    ${acid_hive_env},
    "hive-site": {
        ${acid_hive_site}
        "hive.server2.enable.doAs" : "true",
        "hive.exec.compress.output": "true",
        "hive.merge.mapfiles": "true",
        "hive.exec.post.hooks" : "org.apache.hadoop.hive.ql.hooks.ATSHook,org.apache.atlas.hive.hook.HiveHook",
        "hive.server2.tez.initialize.default.sessions": "true",
        "javax.jdo.option.ConnectionDriverName" : "com.mysql.jdbc.Driver",
        "javax.jdo.option.ConnectionURL" : "jdbc:mysql://${host}/hive?createDatabaseIfNotExist=true",
        "javax.jdo.option.ConnectionUserName": "hive",
	"javax.jdo.option.ConnectionPassword": "${hive_db_password}"
    },
    "mapred-site": {
        "mapreduce.job.reduce.slowstart.completedmaps": "0.7",
        "mapreduce.map.output.compress": "true",
        "mapreduce.output.fileoutputformat.compress": "true"
    },
    "yarn-site": {
        "yarn.acl.enable" : "true"
    },
    "ams-site": {
      "timeline.metrics.cache.size": "100"
    },
    "kafka-broker": {
      "offsets.topic.replication.factor": "1"
    },
    "admin-properties": {
        "policymgr_external_url": "http://localhost:6080",
        "db_root_user": "admin",
        "db_root_password": "BadPass#1",
        "DB_FLAVOR": "POSTGRES",
        "db_user": "rangeradmin",
        "db_password": "BadPass#1",
        "db_name": "ranger",
        "db_host": "localhost"
    },
    "ranger-env": {
        "ranger_admin_username": "admin",
        "ranger_admin_password": "admin",
        "ranger-knox-plugin-enabled" : "No",
        "ranger-storm-plugin-enabled" : "No",
        "ranger-kafka-plugin-enabled" : "Yes",
        "ranger-hdfs-plugin-enabled" : "Yes",
        "ranger-hive-plugin-enabled" : "Yes",
        "ranger-hbase-plugin-enabled" : "Yes",
        "ranger-atlas-plugin-enabled" : "Yes",
        "ranger-yarn-plugin-enabled" : "Yes",
        "is_solrCloud_enabled": "true",
        "xasecure.audit.destination.solr" : "true",
        "xasecure.audit.destination.hdfs" : "true",
        "ranger_privelege_user_jdbc_url" : "jdbc:postgresql://localhost:5432/postgres",
        "create_db_dbuser": "true"
    },
    "ranger-admin-site": {
        "ranger.jpa.jdbc.driver": "org.postgresql.Driver",
        "ranger.jpa.jdbc.url": "jdbc:postgresql://localhost:5432/ranger",
        "ranger.audit.solr.zookeepers": "$(hostname -f):2181/infra-solr",
        "ranger.servicedef.enableDenyAndExceptionsInPolicies": "true"
    },
    "ranger-tagsync-site": {
        "ranger.tagsync.atlas.hdfs.instance.cl1.ranger.service": "${cluster_name}_hadoop",
        "ranger.tagsync.atlas.hive.instance.cl1.ranger.service": "${cluster_name}_hive",
        "ranger.tagsync.atlas.hbase.instance.cl1.ranger.service": "${cluster_name}_hbase",
        "ranger.tagsync.atlas.kafka.instance.cl1.ranger.service": "${cluster_name}_kafka",
        "ranger.tagsync.atlas.atlas.instance.cl1.ranger.service": "${cluster_name}_atlas",
        "ranger.tagsync.atlas.yarn.instance.cl1.ranger.service": "${cluster_name}_yarn",
        "ranger.tagsync.atlas.tag.instance.cl1.ranger.service": "tags"
    },
    "ranger-hive-audit" : {
        "xasecure.audit.is.enabled" : "true",
        "xasecure.audit.destination.hdfs" : "true",
        "xasecure.audit.destination.solr" : "true"
    }
  }
}
EOF

#Check validity of JSON created by the above.

if jq '.' configuration-custom.json; then
  echo "JSON file is valid ..."
else
  echo "Custom config JSON file is invalid! Please fix the source script ..." 1>&2
  exit 1
fi

#TODO: Do something meaningful and graceful if validation fails. Maybe move this cat to to the top of the script so backing out is easier?

sed -i.bak "s/\[security\]/\[security\]\nforce_https_protocol=PROTOCOL_TLSv1_2/"   /etc/ambari-agent/conf/ambari-agent.ini

sudo ambari-agent restart
	
    sleep 40
    service ambari-server status
    #curl -u admin:${ambari_pass} -i -H "X-Requested-By: blah" -X GET ${ambari_url}/hosts
    ./deploy-recommended-cluster.bash

    if [ "${deploy}" = "true" ]; then

        cd ~
        sleep 20
        source ~/ambari-bootstrap/extras/ambari_functions.sh
        ambari_configs
        ambari_wait_request_complete 1
        sleep 5

        #Needed due to BUG-91977: Blueprint bug in Ambari 2.6.0.0
        if ! nc localhost 6080 ; then
           echo "Ranger did not start. Restarting..."

           curl -u admin:${ambari_pass} -i -H 'X-Requested-By: ambari' -X PUT -d '{"RequestInfo": {"context" :"Start RANGER via REST"}, "Body": {"ServiceInfo": {"state": "STARTED"}}}' http://localhost:8080/api/v1/clusters/${cluster_name}/services/RANGER
           sleep 5

           echo "Starting all services..."
           curl -u admin:${ambari_pass} -i -H "X-Requested-By: blah" -X PUT -d  '{"RequestInfo":{"context":"_PARSE_.START.ALL_SERVICES","operation_level":{"level":"CLUSTER","cluster_name":"'"${cluster_name}"'"}},"Body":{"ServiceInfo":{"state":"STARTED"}}}' http://localhost:8080/api/v1/clusters/${cluster_name}/services

           while ! echo exit | nc localhost 21000; do echo "waiting for services to start...."; sleep 10; done
           while ! echo exit | nc localhost 10000; do echo "waiting for hive to come up..."; sleep 10; done
           while ! echo exit | nc localhost 50111; do echo "waiting for hcat to come up..."; sleep 10; done
        fi

        sleep 30

        echo "Adding Hortonia local users ..."
    
          cd /tmp/masterclass/ranger-atlas/HortoniaMunichSetup
          ./04-create-ambari-users.sh

        #TODO: fix adding groups to Hive views
        #curl -u admin:${ambari_pass} -i -H "X-Requested-By: blah" -X PUT http://localhost:8080/api/v1/views/HIVE/versions/1.5.0/instances/AUTO_HIVE_INSTANCE/privileges \
        #   --data '[{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"us_employee","principal_type":"GROUP"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"business_dev","principal_type":"GROUP"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"eu_employee","principal_type":"GROUP"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.ADMINISTRATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.OPERATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"SERVICE.OPERATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"SERVICE.ADMINISTRATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.USER","principal_type":"ROLE"}}]'

        #curl -u admin:${ambari_pass} -i -H 'X-Requested-By: blah' -X PUT http://localhost:8080/api/v1/views/HIVE/versions/2.0.0/instances/AUTO_HIVE20_INSTANCE/privileges \
        #   --data '[{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"us_employee","principal_type":"GROUP"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"business_dev","principal_type":"GROUP"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"eu_employee","principal_type":"GROUP"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.ADMINISTRATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.OPERATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"SERVICE.OPERATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"SERVICE.ADMINISTRATOR","principal_type":"ROLE"}},{"PrivilegeInfo":{"permission_name":"VIEW.USER","principal_name":"CLUSTER.USER","principal_type":"ROLE"}}]'

        #restart Atlas
       sudo curl -u admin:${ambari_pass} -H 'X-Requested-By: blah' -X POST -d "
{
   \"RequestInfo\":{
      \"command\":\"RESTART\",
      \"context\":\"Restart Atlas\",
      \"operation_level\":{
         \"level\":\"HOST\",
         \"cluster_name\":\"${cluster_name}\"
      }
   },
   \"Requests/resource_filters\":[
      {
         \"service_name\":\"ATLAS\",
         \"component_name\":\"ATLAS_SERVER\",
         \"hosts\":\"${host}\"
      }
   ]
}" http://localhost:8080/api/v1/clusters/${cluster_name}/requests




        ## update zeppelin notebooks and upload to HDFS
        curl -sSL https://raw.githubusercontent.com/hortonworks-gallery/zeppelin-notebooks/master/update_all_notebooks.sh | sudo -E sh
        sudo -u zeppelin hdfs dfs -rmr /user/zeppelin/notebook/*
        sudo -u zeppelin hdfs dfs -put /usr/hdp/current/zeppelin-server/notebook/* /user/zeppelin/notebook/

      #update zeppelin configs to include ivanna/joe/diane users
      /var/lib/ambari-server/resources/scripts/configs.py -u admin -p ${ambari_pass} --host localhost --port 8080 --cluster ${cluster_name} -a get -c zeppelin-shiro-ini \
        | sed -e '1,2d' \
        -e "s/admin = admin, admin/etl_user = ${ambari_pass},admin/"  \
        -e "s/user1 = user1, role1, role2/ivanna_eu_hr = ${ambari_pass}, admin/" \
        -e "s/user2 = user2, role3/michelle_dpo = ${ambari_pass}, admin/" \
        -e "s/user3 = user3, role2/joe_analyst = ${ambari_pass}, admin/" \
        > /tmp/zeppelin-env.json


      /var/lib/ambari-server/resources/scripts/configs.py -u admin -p ${ambari_pass} --host localhost --port 8080 --cluster ${cluster_name} -a set -c zeppelin-shiro-ini -f /tmp/zeppelin-env.json
      sleep 5



      #restart Zeppelin
      sudo curl -u admin:${ambari_pass} -H 'X-Requested-By: blah' -X POST -d "
{
   \"RequestInfo\":{
      \"command\":\"RESTART\",
      \"context\":\"Restart Zeppelin\",
      \"operation_level\":{
         \"level\":\"HOST\",
         \"cluster_name\":\"${cluster_name}\"
      }
   },
   \"Requests/resource_filters\":[
      {
         \"service_name\":\"ZEPPELIN\",
         \"component_name\":\"ZEPPELIN_MASTER\",
         \"hosts\":\"${host}\"
      }
   ]
}" http://localhost:8080/api/v1/clusters/${cluster_name}/requests



    while ! echo exit | nc localhost 21000; do echo "waiting for atlas to come up..."; sleep 10; done
    sleep 30

    # curl -u admin:${ambari_pass} -i -H 'X-Requested-By: blah' -X POST -d '{"RequestInfo": {"context" :"ATLAS Service Check","command":"ATLAS_SERVICE_CHECK"},"Requests/resource_filters":[{"service_name":"ATLAS"}]}' http://localhost:8080/api/v1/clusters/${cluster_name}/requests

    ## update ranger to support deny policies
    ranger_curl="curl -u admin:admin"
    ranger_url="http://localhost:6080/service"

#TODO: Fix these curl lines - they did not work.

    ${ranger_curl} ${ranger_url}/public/v2/api/servicedef/name/hive \
      | jq '.options = {"enableDenyAndExceptionsInPolicies":"true"}' \
      | jq '.policyConditions = [
    {
          "itemId": 1,
          "name": "resources-accessed-together",
          "evaluator": "org.apache.ranger.plugin.conditionevaluator.RangerHiveResourcesAccessedTogetherCondition",
          "evaluatorOptions": {},
          "label": "Resources Accessed Together?",
          "description": "Resources Accessed Together?"
    },{
        "itemId": 2,
        "name": "not-accessed-together",
        "evaluator": "org.apache.ranger.plugin.conditionevaluator.RangerHiveResourcesNotAccessedTogetherCondition",
        "evaluatorOptions": {},
        "label": "Resources Not Accessed Together?",
        "description": "Resources Not Accessed Together?"
    }
    ]' > hive.json

    ${ranger_curl} -i \
      -X PUT -H "Accept: application/json" -H "Content-Type: application/json" \
      -d @hive.json ${ranger_url}/public/v2/api/servicedef/name/hive
    sleep 10

  #create tag service repo in Ranger called tags
  ${ranger_curl} ${ranger_url}/public/v2/api/service -X POST  -H "Content-Type: application/json"  -d @- <<EOF
{
  "name":"tags",
  "description":"tags service from API",
  "type": "tag",
  "configs":{},
  "isActive":true
}
EOF


   #associate tag service with Hive/Hbase/Kafka Ranger repos
   for component in hive hbase kafka ; do
     echo "Adding tags service to Ranger $component repo..."
     ${ranger_curl} ${ranger_url}/public/v2/api/service | jq ".[] | select (.type==\"${component}\")"  > tmp.json
     cat tmp.json | jq '. |= .+  {"tagService":"tags"}' > tmp-updated.json
     ${ranger_curl} ${ranger_url}/public/v2/api/service/name/${cluster_name}_${component} -X PUT  -H "Content-Type: application/json"  -d @tmp-updated.json
   done


    cd /tmp/masterclass/ranger-atlas/Scripts/
    echo "importing ranger Tag policies.."
    < ranger-policies-tags.json jq '.policies[].service = "tags"' > ranger-policies-tags_apply.json
    ${ranger_curl} -X POST \
    -H "Content-Type: multipart/form-data" \
    -H "Content-Type: application/json" \
    -F 'file=@ranger-policies-tags_apply.json' \
              "${ranger_url}/plugins/policies/importPoliciesFromFile?isOverride=true&serviceType=tag"

    echo "import ranger Hive policies..."
    < ranger-policies-enabled.json jq '.policies[].service = "'${cluster_name}'_hive"' > ranger-policies-apply.json
    ${ranger_curl} -X POST \
    -H "Content-Type: multipart/form-data" \
    -H "Content-Type: application/json" \
    -F 'file=@ranger-policies-apply.json' \
              "${ranger_url}/plugins/policies/importPoliciesFromFile?isOverride=true&serviceType=hive"

    echo "import ranger HDFS policies..." #to give hive access to /hive_data HDFS dir
    < ranger-hdfs-policies.json jq '.policies[].service = "'${cluster_name}'_hadoop"' > ranger-hdfs-policies-apply.json
    ${ranger_curl} -X POST \
    -H "Content-Type: multipart/form-data" \
    -H "Content-Type: application/json" \
    -F 'file=@ranger-hdfs-policies-apply.json' \
              "${ranger_url}/plugins/policies/importPoliciesFromFile?isOverride=true&serviceType=hdfs"

    echo "import ranger kafka policies..." #  to give ANONYMOUS access to kafka or Atlas won't work
    < ranger-kafka-policies.json jq '.policies[].service = "'${cluster_name}'_kafka"' > ranger-kafka-policies-apply.json
    ${ranger_curl} -X POST \
    -H "Content-Type: multipart/form-data" \
    -H "Content-Type: application/json" \
    -F 'file=@ranger-kafka-policies-apply.json' \
              "${ranger_url}/plugins/policies/importPoliciesFromFile?isOverride=true&serviceType=kafka"


    echo "import ranger hbase policies..."
    < ranger-hbase-policies.json jq '.policies[].service = "'${cluster_name}'_hbase"' > ranger-hbase-policies-apply.json
    ${ranger_curl} -X POST \
    -H "Content-Type: multipart/form-data" \
    -H "Content-Type: application/json" \
    -F 'file=@ranger-hbase-policies-apply.json' \
              "${ranger_url}/plugins/policies/importPoliciesFromFile?isOverride=true&serviceType=hbase"



    sleep 40

    cd /tmp/masterclass/ranger-atlas/HortoniaMunichSetup
    ./01-atlas-import-classification.sh
    #./02-atlas-import-entities.sh      ## replaced with 09-associate-entities-with-tags.sh
    ./03-update-servicedefs.sh


    cd /tmp/masterclass/ranger-atlas/HortoniaMunichSetup
    su hdfs -c ./05-create-hdfs-user-folders.sh
    su hdfs -c ./06-copy-data-to-hdfs.sh




    #Enable kerberos
    if [ "${enable_kerberos}" = true  ]; then
       ./08-enable-kerberos.sh
    fi

    #wait until Hive is up
    while ! echo exit | nc localhost 10000; do echo "waiting for hive to come up..."; sleep 10; done
    while ! echo exit | nc localhost 50111; do echo "waiting for hcat to come up..."; sleep 10; done

    sleep 30


    #kill any previous Hive/tez apps to clear queue before creating tables

    if [ "${enable_kerberos}" = true  ]; then
      kinit -kVt /etc/security/keytabs/rm.service.keytab rm/$(hostname -f)@${kdc_realm}
    fi
    #kill any previous Hive/tez apps to clear queue before hading cluster to end user
    for app in $(yarn application -list | awk '$2==hive && $3==TEZ && $6 == "ACCEPTED" || $6 == "RUNNING" { print $1 }')
    do
        yarn application -kill  "$app"
    done


    #create tables

    if [ "${enable_kerberos}" = true  ]; then
       ./07-create-hive-schema-kerberos.sh
    else
       ./07-create-hive-schema.sh
    fi


    if [ "${enable_kerberos}" = true  ]; then
      kinit -kVt /etc/security/keytabs/rm.service.keytab rm/$(hostname -f)@${kdc_realm}
    fi
    #kill any previous Hive/tez apps to clear queue before hading cluster to end user
    for app in $(yarn application -list | awk '$2==hive && $3==TEZ && $6 == "ACCEPTED" || $6 == "RUNNING" { print $1 }')
    do
        yarn application -kill  "$app"
    done


    cd /tmp/masterclass/ranger-atlas/HortoniaMunichSetup

    #create kafka topics and populate data - do it after kerberos to ensure Kafka Ranger plugin enabled
    ./08-create-hbase-kafka.sh

     #import Atlas entities
     ./09-associate-entities-with-tags.sh

    echo "Done."
    fi


echo "--------------------------"
echo "--------------------------"
echo "Automated portion of setup is complete, next please create the tag repo in Ranger, associate with Hive and import tag policies"
echo "See https://github.com/abajwa-hw/masterclass/blob/master/ranger-atlas/README.md for more details"
echo "Once complete, see here for walk through of demo: https://community.hortonworks.com/articles/151939/hdp-securitygovernance-demo-kit.html"

fi
