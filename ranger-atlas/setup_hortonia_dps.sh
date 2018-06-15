#!/usr/bin/env bash
# Launch Centos 7 Vm 
# Then run:
# curl -sSL https://github.com/hw-rdobson/masterclass/edit/master/ranger-atlas/setup_hortonia_dps.sh/raw | sudo -E sh  

########################################################################
########################################################################
## variables

export HOME=${HOME:-/root}
export TERM=xterm
#detect name of cluster
output=`curl -u admin:admin -i -H 'X-Requested-By: ambari'  http://localhost:8080/api/v1/clusters`
 
CLUSTER=`echo $output | sed -n 's/.*"cluster_name" : "\([^\"]*\)".*/\1/p'`
#overridable vars
export stack=$CLUSTER    #cluster name
export ambari_pass=${ambari_pass:-admin}  #ambari password
export ambari_services=${ambari_services:-HBASE HDFS MAPREDUCE2 PIG YARN HIVE ZOOKEEPER SLIDER AMBARI_INFRA TEZ RANGER ATLAS KAFKA SPARK2 ZEPPELIN KNOX BEACON DPPROFILER}   #HDP services
export ambari_stack_version=${ambari_stack_version:-2.6}  #HDP Version
export host_count=${host_count:-1}      #number of nodes, defaults to 1
export enable_hive_acid=${enable_hive_acid:-true}   #enable Hive ACID?
export enable_kerberos=${enable_kerberos:-true}
export kdc_realm=${kdc_realm:-HWX.COM}      #KDC realm
export ambari_version="${ambari_version:-2.6.2.0}"   #Need Ambari 2.6.0+ to avoid Zeppelin BUG-92211
export ambari_admin=${ambari_admin:-admin}
#Database passwords
export db_password=${db_password:-StrongPassword}
export hive_db_password=${hive_db_password:-H!veRox} #using default user hive on existing MariaDB database
export beacon_db_password=${beacon_db_password:-8eaconRox} #using default user beacon on existing MariaDB database

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
export install_ambari_server=false
export deploy=false

export host=$(hostname -f)
export ambari_host=$(hostname -f)
## overrides
#export ambari_stack_version=2.6
#export ambari_repo=""

export install_ambari_server ambari_pass host_count ambari_services
export ambari_password cluster_name recommendation_strategy

########################################################################
########################################################################
## tutorial users
## update ambari password to one used by scripts
export ambari_pass2=${ambari_pass2:-BadPass#1}


echo "Installing Hortonia Bank scripts ..."

#download hortonia scripts
cd /tmp
git clone https://github.com/abajwa-hw/masterclass

cd /tmp/masterclass/ranger-atlas/HortoniaMunichSetup
# Temp fix
chown -R root:root /tmp/masterclass
chmod -R 777 /tmp/masterclass
#chmod +x *.sh
sh ./04-create-os-users.sh    
#also need anonymous user for kafka Ranger policy and dpprofiler for DSS
useradd ANONYMOUS
useradd dpprofiler


########################################################################
########################################################################
##
if [ "${enable_hive_acid}" = true  ]; then
		acid_hive_env="\"hive-env\": { \"hive_txn_acid\": \"on\" }"


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

    service ambari-server status
    #curl -u admin:${ambari_pass} -i -H "X-Requested-By: blah" -X GET ${ambari_url}/hosts
    #./deploy-recommended-cluster.bash


        echo "Adding Hortonia local users ..."
    
          cd /tmp/masterclass/ranger-atlas/HortoniaMunichSetup
          sh ./04-create-ambari-users.sh


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

echo "**** reset ambari password *****"
#curl  -u admin:admin -H "X-Requested-By: Goll" -X PUT -d "{ \"Users\": { \"user_name\": \"admin\", \"${ambari_pass2}": \"admin\", \"password\": \"${ambari_pass}\" }}" ${ambari_host}:8080/api/v1/users/admin

echo "--------------------------"
echo "--------------------------"
echo "Automated portion of setup is complete, next please create the tag repo in Ranger, associate with Hive and import tag policies"
echo "See https://github.com/abajwa-hw/masterclass/blob/master/ranger-atlas/README.md for more details"
echo "Once complete, see here for walk through of demo: https://community.hortonworks.com/articles/151939/hdp-securitygovernance-demo-kit.html"

