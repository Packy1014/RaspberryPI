#!/bin/bash
echo "Backup is going to start, please enter user name..."
read username
echo "Please enter usergroup"
read usergroup

img=rpibackup.img
echo "Image name : ${img}"
readonly bootSize=`df -l | grep /boot | awk '{print $2}'`
readonly rootSize=`df -l | grep /dev/root | awk '{print $3}'`
readonly imgSize=`echo $bootSize $rootSize | awk '{print int(($1+$2)*1.3/1024)}'`
echo "Boot size : ${bootSize} KB"
echo "Root size : ${rootSize} KB"
echo "Image size : ${imgSize} MB"

sudo apt-get install dosfstools dump parted kpartx

sudo mkdir backupimg

cd backupimg

sudo mkdir src_boot src_Root

sudo mount -t vfat -o uid=pi,gid=pi,umask=0000 /dev/sda1 ./src_boot/

sudo mount -t ext4 /dev/sda2 ./src_Root/

sudo dd if=/dev/zero of=${img} bs=1M count=${imgSize}

sudo parted ${img} --script -- mklabel msdos
sudo parted ${img} --script -- mkpart primary fat32 8192s 122479s
sudo parted ${img} --script -- mkpart primary ext4 122880s -1

sleep 3s

readonly loopDevice=`sudo losetup -f --show $img`

sleep 3s

sudo kpartx -va ${loopDevice}

sleep 5s

readonly loopDeviceBoot="${loopDevice%/*}/mapper/${loopDevice##*/}p1"
readonly loopDeviceRoot="${loopDevice%/*}/mapper/${loopDevice##*/}p2"

sudo mkfs.vfat -n boot ${loopDeviceBoot}
sudo mkfs.ext4 ${loopDeviceRoot}

sudo mkdir tgt_boot tgt_Root
sudo mount -t vfat -o uid=pi,gid=pi,umask=0000 ${loopDeviceBoot} ./tgt_boot/
sudo mount -t ext4 ${loopDeviceRoot} ./tgt_Root/

sudo cp -rfp ./src_boot/* ./tgt_boot/
sudo chmod 777 tgt_Root
sudo chown "${username}.${usergroup}" tgt_Root
sudo rm -rf ./tgt_Root/*
cd tgt_Root
sudo dump -0uaf - ../src_Root/ | sudo restore -rf -
cd ..

readonly loopDeviceBootInfo=`sudo blkid | grep ${loopDeviceBoot}`
readonly loopDeviceRootInfo=`sudo blkid | grep ${loopDeviceRoot}`

readonly loopDeviceBootUUIDTemp=${loopDeviceBootInfo##*PARTUUID=\"}
readonly loopDeviceRootUUIDTemp=${loopDeviceRootInfo##*PARTUUID=\"}

readonly loopDeviceBootUUID=${loopDeviceBootUUIDTemp%\"*}
readonly loopDeviceRootUUID=${loopDeviceRootUUIDTemp%\"*}

sudo sed -i "s/root=PARTUUID=[A-Za-z0-9-]*/root=PARTUUID=${loopDeviceRootUUID}/g" ./tgt_boot/cmdline.txt
sudo sed -i "s/PARTUUID=[A-Za-z0-9-]*\s*\/boot/PARTUUID=${loopDeviceBootUUID}  \/boot/g" ./tgt_Root/etc/fstab
sudo sed -i "s/PARTUUID=[A-Za-z0-9-]*\s*\/\s/PARTUUID=${loopDeviceRootUUID}  \//g" ./tgt_Root/etc/fstab


sudo umount src_boot src_Root tgt_boot tgt_Root

sudo kpartx -d /dev/loop0
sudo losetup -d /dev/loop0

sudo rmdir src_boot src_Root tgt_boot tgt_Root