#!/bin/bash

VERSION=7.$( date  +%Y%m%d )

DateStamp=$( date  +%Y%m%d_%H%M%S )
GitDir=$(pwd)
BuildDir=$1
LogFile=${BuildDir}/log
mkdir -p ${BuildDir}
# Make it absolute
BuildDir=$(cd $BuildDir && pwd)
OstreeRepoDir=/${BuildDir}/repo && mkdir -p $OstreeRepoDir
ln -s ${OstreeRepoDir} ${BuildDir}/repo

set -x
set -e
set -o pipefail

cd ${BuildDir}

systemctl start docker
systemctl start libvirtd

## This part creates an install tree and install iso 

echo '---------- installer ' >> ${LogFile}
# only build the installer if its not there already
if [ ! -e ${BuildDir}/images/centos-atomic-host-7.iso ]; then
  rpm-ostree-toolbox installer --overwrite --ostreerepo ${BuildDir}/repo -c  ${GitDir}/config.ini -o ${BuildDir}/installer |& tee ${LogFile}
fi

# we likely need to push the installer content to somewhere the following kickstart
#  can pick the content from ( does it otherwise work with a file:/// url ? unlikely )
python -m SimpleHTTPServer 8000 &

# build the backing image we want to convert into a live disk
rpm-ostree-toolbox imagefactory --overwrite --tdl ${GitDir}/atomic-7.1.tdl -c  ${GitDir}/config.ini -i kvm -k ${GitDir}/live.ks -o ${BuildDir}/virt |& tee ${LogFile}

# copy the image off, convert to RAW, have livemedia-creator have a go.
mkdir ${BuildDir}/live
cat ${BuildDir}/virt/centos-atomic-host-7.qcow2.gz | gunzip > ${BuildDir}/live/qcow2
qemu-img convert -O raw ${BuildDir}/live/qcow2 ${BuildDir}/live/raw
/usr/sbin/livemedia-creator --make-ostree-live --disk-image=${BuildDir}/live/raw --live-rootfs-keep-size --resultdir=${BuildDir}/live/out

# This does not currently work, due to issues in ImgFac:
#rpm-ostree-toolbox liveimage -c ${GitDir}/config.ini --tdl ${GitDir}/atomic-7.1.tdl  -o pxe-to-live -k ${GitDir}/atomic-7.1-cloud.ks --ostreerepo http://192.168.122.1:8000/repo


## kill the last background job, to shut off the python simpleserver
kill $!


