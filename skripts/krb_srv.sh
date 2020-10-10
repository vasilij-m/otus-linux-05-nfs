#!/bin/bash

KDC_NAME='krb-srv.nfs.lab'
REALM='NFS.LAB'
DOMAIN='nfs.lab'
KRB_MASTER_KEY='M@sterKey'
KRB_ROOT_PASSWORD='r00tp@ss'
KRB_USER='nfs_user'
KRB_USER_PASS='nfsp@ss'

yum install -y krb5-server krb5-libs krb5-workstation

sed -i -e "
s/# default_realm = EXAMPLE.COM/ default_realm = ${REALM}/
s/# EXAMPLE.COM = {/ ${REALM} = {/
s/#  kdc = kerberos.example.com/  kdc = ${KDC_NAME}/
s/#  admin_server = kerberos.example.com/  admin_server = ${KDC_NAME}/
s/# }/ }/
s/# .example.com = EXAMPLE.COM/ .${DOMAIN} = ${REALM}/
s/# example.com = EXAMPLE.COM/ ${DOMAIN} = ${REALM}/" /etc/krb5.conf

sed -i -e "
s/ EXAMPLE.COM = {/ ${REALM} = {/
s/  #master_key_type = aes256-cts/  master_key_type = aes256-cts/" /var/kerberos/krb5kdc/kdc.conf

sed -i "s/EXAMPLE.COM/${REALM}/" /var/kerberos/krb5kdc/kadm5.acl

kdb5_util create -s -r ${REALM} <<EOF
${KRB_MASTER_KEY}
${KRB_MASTER_KEY}
EOF

kadmin.local -q "addprinc -pw ${KRB_ROOT_PASSWORD} root/admin"
kadmin.local -q "addprinc -pw ${KRB_USER_PASS} ${KRB_USER}"

systemctl start krb5kdc.service kadmin.service
systemctl enable krb5kdc.service kadmin.service
