#!/bin/bash

HOST_NAME=$(hostname)
KDC_NAME='krb-srv.nfs.lab'
REALM='NFS.LAB'
DOMAIN='nfs.lab'
KRB_MASTER_KEY='M@sterKey'
KRB_ROOT_PASSWORD='r00tp@ss'
KRB_USER='nfs_user'
KRB_USER_PASS='nfsp@ss'
NFS_SERVER='nfs-srv'
NFS_CLIENT='nfs-cl'

yum install -y krb5-workstation krb5-libs

sed -i -e "
s/# default_realm = EXAMPLE.COM/ default_realm = ${REALM}/
s/# EXAMPLE.COM = {/ ${REALM} = {/
s/#  kdc = kerberos.example.com/  kdc = ${KDC_NAME}/
s/#  admin_server = kerberos.example.com/  admin_server = ${KDC_NAME}/
s/# }/ }/
s/# .example.com = EXAMPLE.COM/ .${DOMAIN} = ${REALM}/
s/# example.com = EXAMPLE.COM/ ${DOMAIN} = ${REALM}/" /etc/krb5.conf

kadmin -p root/admin -w ${KRB_ROOT_PASSWORD} -q "addprinc -randkey host/${HOST_NAME}"
kadmin -p root/admin -w ${KRB_ROOT_PASSWORD} -q "ktadd -k /etc/krb5.keytab host/${HOST_NAME}"

if [[ $HOST_NAME == "${NFS_SERVER}.${DOMAIN}" ]]; then
    kadmin -p root/admin -w ${KRB_ROOT_PASSWORD} -q "addprinc -randkey nfs/${NFS_SERVER}.${DOMAIN}"
    kadmin -p root/admin -w ${KRB_ROOT_PASSWORD} -q "ktadd nfs/${NFS_SERVER}.${DOMAIN}"
    systemctl restart nfs-server
elif [[ $HOST_NAME == "${NFS_CLIENT}.${DOMAIN}" ]]; then
    kadmin -p root/admin -w ${KRB_ROOT_PASSWORD} -q "addprinc -randkey nfs/${NFS_CLIENT}.${DOMAIN}"
    kadmin -p root/admin -w ${KRB_ROOT_PASSWORD} -q "ktadd nfs/${NFS_CLIENT}.${DOMAIN}"
    systemctl restart nfs-client.target
fi
