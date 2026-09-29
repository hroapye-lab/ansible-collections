#! /bin/bash

rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org

yum install -y https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm

sed -i s#http://elrepo.org/linux#https://chinanet.mirrors.ustc.edu.cn/elrepo#g /etc/yum.repos.d/elrepo.repo
sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/elrepo.repo

yum --enablerepo=elrepo-kernel install -y kernel-lt

