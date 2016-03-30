#!/bin/bash

usage() {
        echo "mydocker.sh root_dir ip_addr cpu_usage"
        echo "例如: sh mydocker.sh /images/fedora/ 192.168.1.10 10"
        echo "上面的意思是，启动一个fedora虚拟机，ip地址为192.168.1.10，CPU最多10%"

        echo "需要事先创建一个网桥mydocker"
        echo "如果没有brctl命令，ubuntu使用apt-get install bridge-utils安装"
        echo "比如网桥的ip为192.168.1.1/24"
        echo "那么虚拟机的地址应该和这个网桥一个网段,自己控制IP不重复"
        echo "创建网桥的shell"
        echo "1. brctl addbr mydocker"
        echo "2. ip link set mydocker up"
        echo "3. ip addr add 192.168.1.1/24 dev mydocker"
}

#检查是否有root权限
if [ $UID -ne 0 ]
then
        echo "must run as root"
        exit 1
fi
if [ $# != 3 ]
then
        usage
        exit 1
fi
#获取一个时间戳用于命名
timestamp=`date +%s`

################资源隔离#####################
#为父进程创建一个cgroup，仅对cpu做限制,$3是CPU使用率
#比如$3是10，那1s最多使用0.1s,也就是10000us,使用率后加3个0就是us数
cgroup=CG"$timestamp"
mkdir -p /sys/fs/cgroup/cpu/$cgroup
cfs_quota_us="$3"000
echo $cfs_quota_us > /sys/fs/cgroup/cpu/$cgroup/cpu.cfs_quota_us
echo $$ > /sys/fs/cgroup/cpu/$cgroup/tasks



################名字空间隔离#####################
namespace=NS"$timestamp"
ip netns add $namespace

#创建一对虚拟设备A,B
PEER_A=A"$timestamp"
PEER_B=B"$timestamp"
ip link add $PEER_A type veth peer name $PEER_B

#把B放到新的名字空间，改名为eth0，分配地址
ip link set $PEER_B netns $namespace
ip netns exec $namespace ip link set dev $PEER_B name eth0
ip netns exec $namespace ip link set eth0 up
ip netns exec $namespace ip addr add $2/24 dev eth0

#把A连到主机的一个网桥上
brctl addif mydocker $PEER_A
ip link set $PEER_A up

###############运行环境隔离#######################
#在新的namespace里，在指定的root fs里启动/bin/bash,这次镜像$1被只读挂载，然后上层有一个rw层
RW_LAYER=/tmp/"$timestamp"
mkdir -p "$RW_LAYER"
mount -t aufs -o br="$RW_LAYER":$1=ro none "$RW_LAYER"
ip netns exec $namespace chroot "$RW_LAYER"

