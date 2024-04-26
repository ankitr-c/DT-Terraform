#!/bin/bash
yum install nfs-utils -y
mkdir /home/centos/NFS_Mount

sleep 360

mount -t nfs -o timeo=300 ${nfs_ip}:/testing /home/centos/NFS_Mount
