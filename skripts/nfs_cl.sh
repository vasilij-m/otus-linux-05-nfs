#!/bin/bash

NFS_MOUNT_DIR='/media/nfs_share'
NFS_SERVER_FQDN='nfs-srv.nfs.lab'
NFS_SHARE_PATH='/media/nfs_share'
NFS_MOUNT_OPTIONS='vers=4,sec=krb5,proto=tcp'

mkdir ${NFS_MOUNT_DIR}
mount -t nfs -o ${NFS_MOUNT_OPTIONS} ${NFS_SERVER_FQDN}:${NFS_SHARE_PATH} ${NFS_MOUNT_DIR}

cat > /etc/systemd/system/media-nfs_share.mount <<EOF
[Unit]
Description=Mount NFS Share
Requires=network-online.service
After=network-online.service

[Mount]
What=${NFS_SERVER_FQDN}:${NFS_SHARE_PATH}
Where=${NFS_MOUNT_DIR}
Type=nfs
Options=${NFS_MOUNT_OPTIONS}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable media-nfs_share.mount
