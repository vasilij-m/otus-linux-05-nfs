#!/bin/bash

NFS_DIR='/media/nfs_share'
ALLOWED_NFS_CLIENTS='192.168.10.0/24'
NFS_DIR_OPTIONS='rw,sec=krb5'

yum install -y nfs-utils
systemctl enable nfs --now
mkdir -p ${NFS_DIR}/upload/
chown -R nfsnobody:nfsnobody ${NFS_DIR}
chmod -R 777 ${NFS_DIR}

echo "${NFS_DIR} ${ALLOWED_NFS_CLIENTS}(${NFS_DIR_OPTIONS})" >> /etc/exports
systemctl restart nfs-server
