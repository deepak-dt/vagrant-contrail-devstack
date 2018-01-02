#! /bin/bash

function restart_intf_vrouter_dpdk() {
    source /etc/contrail/contrail-compute.conf
    if [ -e $VHOST_CFG ]; then
	source $VHOST_CFG
    else
	DEVICE=vhost0
    fi

    if is_ubuntu; then
	# bring up vhost0
	sudo ifdown -i /tmp/interfaces $DEVICE
	sudo ifup -i /tmp/interfaces $DEVICE
	echo "Sleeping 10 seconds to allow link state to settle"
	sleep 10

	sudo ifconfig $DEVICE hw ether $HWADDR
	sudo route add default gw $GATEWAY $DEVICE
    else
        sudo ifdown $dev 
        sleep 10
        sudo ifup $DEVICE         
        sleep 10
    fi
}

function configure_vrouter_dpdk() {
    source /etc/contrail/contrail-compute.conf
    EXT_DEV=$dev
    if [ -e $VHOST_CFG ]; then
	source $VHOST_CFG
    else
	DEVICE=vhost0
        IPADDR=$(sudo ifconfig $EXT_DEV | sed -ne 's/.*inet [[addr]*]*[: ]*\([0-9.]*\).*/\1/i p')
        NETMASK=$(sudo ifconfig $EXT_DEV | sed -ne 's/.*[[net]*]*mask[: *]\([0-9.]*\).*/\1/i p')

    fi

    DEV_MAC=$HWADDR
    dpdk_dev=0

    # don't die in small memory environments
    echo "Creating vhost interface: $DEVICE."
    VIF=/usr/bin/vif

    sudo $VIF --create $DEVICE --mac $DEV_MAC \
        || echo "Error creating interface: $DEVICE"

    echo "Adding $dev to vrouter"
    sudo $VIF --add $dpdk_dev --mac $DEV_MAC --vrf 0 --vhost-phys --type physical --pmd --transport pmd --id $dpdk_dev\
	|| echo "Error adding $dev to vrouter"

    echo "Adding $DEVICE to vrouter"
    sudo $VIF --add $DEVICE --mac $DEV_MAC --vrf 0 --xconnect $dpdk_dev --type vhost --pmd --transport pmd --id $(($dpdk_dev+1))\
	|| echo "Error adding $DEVICE to vrouter"

    if is_ubuntu; then

	# copy eth0 interface params, routes, and dns to a new
	# interfaces file for vhost0
	(
	cat <<EOF
iface $dev inet manual

iface $DEVICE inet static
EOF
	echo " hwaddr $HWADDR"
        echo " address $IPADDR"
	echo " broadcast $BROADCAST"
        echo " netmask $NETMASK"
        #echo " gateway $GATEWAY"

	perl -ne '/^nameserver ([\d.]+)/ && push(@dns, $1); 
END { @dns && print(" dns-nameservers ", join(" ", @dns), "\n") }' /etc/resolv.conf
) >/tmp/interfaces

	# bring up vhost0
	sudo ifdown -i /tmp/interfaces $DEVICE
	sudo ifup -i /tmp/interfaces $DEVICE
	echo "Sleeping 10 seconds to allow link state to settle"
	sleep 10

	sudo ifconfig $DEVICE hw ether $HWADDR
	sudo route add default gw $GATEWAY $DEVICE
    else
        sudo ifdown $dev 
        sleep 10
        sudo ifup $DEVICE         
        sleep 10
    fi
}

# take over physical interface
function start_vrouter_dpdk() {

    CORE_MASK=2

    ##################################
    # Input network interfaces to 
    # bind with DPDK
    ##################################
    declare -a nic_arr=()
    nic_index=0
    read -p "Enter the network interface name to bind with DPDK (for ex. eth0); press 'enter' to exit: " nic
    until [ "a$nic" = "a" ];do
       nic_arr[$nic_index]="$nic"
       echo -e "${nic_arr[@]}"
       ((nic_index++))
       read -p "Enter the network interface name to bind with DPDK (for ex. eth0); press 'enter' to exit: " nic
    done

    ##################################
    # Unbind NICs from DPDK
    ##################################
    cd $CONTRAIL_SRC/third_party/dpdk/tools

    arr=""
    pci=`sudo ./dpdk_nic_bind.py --status | grep "drv=igb_uio" | awk '{print $1}'`

    if [[ -n "$pci" ]]; then
        arr=`echo slave=$pci | sed -e 's, ,\,slave=,'`
    fi

    set -- $pci

    for pci_elem in $@; do
        echo "unbind $pci_elem from DPDK to $DRV"
        sudo ./dpdk_nic_bind.py -b $DRV $pci_elem && echo "OK"
    done

    # TODO: how to find first MAC and firstBCAST in case NICs are already bound with DPDK?
    first_mac=`sudo ifconfig | grep $nic_arr | awk '{print $5}'`
    first_bcast=`sudo ifconfig $nic_arr|grep Bcast|awk '/Bcast/{print substr($3,7)}'`

    ##################################
    # Load igb_uio, kni modules
    # Setup Huges-pages
    ##################################
    while true; do
        read -p "Load Igb_uio, kni modules; setup huge_pages. Press 'y' if done, 'n' to exit: " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit; break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

    ##################################
    # Bind NICs to DPDK
    ##################################
    cd $CONTRAIL_SRC/third_party/dpdk/tools

    for i in "${nic_arr[@]}"
    do
        pci=`sudo ./dpdk_nic_bind.py --status | grep $i | awk '{print $1}'`
        
        if [[ -n "$pci" ]]; then
            sudo ifconfig $i down
            sudo ./dpdk_nic_bind.py --bind=igb_uio $i
            slave_pci="slave=$pci" 
	    if [[ -n "$arr" ]]; then
                arr="$arr,${slave_pci}"
	    else
                arr="${slave_pci}"
            fi
            echo ${arr}            
        fi
    done

    ##################################
    # Edit ifcfg-vhost0
    ##################################
    sed -i.bak 's/^\(HWADDR=\).*/\1'$first_mac'/' /etc/sysconfig/network-scripts/ifcfg-vhost0
    if [ -z $(grep "BROADCAST=" /etc/sysconfig/network-scripts/ifcfg-vhost0) ]; then
        echo "BROADCAST=$first_bcast" >> /etc/sysconfig/network-scripts/ifcfg-vhost0
    fi

    ##################################
    # Edit contrail-vrouter-agent.conf
    ##################################
    if [ $(grep "platform=dpdk" /etc/contrail/contrail-vrouter-agent.conf | wc -l) = 0 ]; then
        sed -i.bak '/\[SANDESH\]/i platform=dpdk' /etc/contrail/contrail-vrouter-agent.conf
    fi

    if [ $(grep "physical_interface_mac =" /etc/contrail/contrail-vrouter-agent.conf | wc -l) = 0 ]; then
        sed -i.bak '/\[SANDESH\]/i physical_interface_mac = '$first_mac'' /etc/contrail/contrail-vrouter-agent.conf
        sed -i.bak '/\[SANDESH\]/i \ ' /etc/contrail/contrail-vrouter-agent.conf
    fi

    if [ $(grep "#routing_instance" /etc/contrail/contrail-vrouter-agent.conf | wc -l) = 0 ]; then
        sed -i.bak 's/routing_instance = default/#routing_instance = default/' /etc/contrail/contrail-vrouter-agent.conf
    fi

    if [ $(grep "#ip_blocks = 11.0.0.0" /etc/contrail/contrail-vrouter-agent.conf | wc -l) = 0 ]; then
        sed -i.bak 's/ip_blocks = 11.0.0.0/#ip_blocks = 11.0.0.0/' /etc/contrail/contrail-vrouter-agent.conf
    fi

    if [ $(grep "#interface = vgw" /etc/contrail/contrail-vrouter-agent.conf | wc -l) = 0 ]; then
        sed -i.bak 's/interface = vgw/#interface = vgw/' /etc/contrail/contrail-vrouter-agent.conf
    fi

    sed -i.bak 's/^\(# backup_enable=\).*/backup_enable=false/' /etc/contrail/contrail-vrouter-agent.conf
    sed -i.bak 's/^\(# restore_enable=\).*/restore_enable=false/' /etc/contrail/contrail-vrouter-agent.conf


    ##################################
    # Bond related configuration
    ##################################
    while true; do
        read -p "Do you wish to create bond interface?" yn
        case $yn in
            [Yy]* ) bond_enabled=true; break;;
            [Nn]* ) bond_enabled=false; break;;
            * ) echo "Please answer yes or no.";;
        esac
    done

    if [ $bond_enabled = true ] ; then 
        if [ $(grep "physical_interface_address = " /etc/contrail/contrail-vrouter-agent.conf | wc -l) = 0 ]; then
            sed -i.bak '/\[SANDESH\]/i physical_interface_address = 0000:00:00.0 ' /etc/contrail/contrail-vrouter-agent.conf
        else
	    sed -i.bak 's/^\(physical_interface_address = \).*/\10000:00:00.0/' /etc/contrail/contrail-vrouter-agent.conf
	fi

        sed -i.bak 's/^\(physical_interface = \).*/\1eth_bond0/' /etc/contrail/contrail-vrouter-agent.conf
        sed -i.bak 's/^\(dev=\).*/\1eth_bond0/' /etc/contrail/contrail-compute.conf

        VDEV_ARGS="--vdev "eth_bond0,mode=0,xmit_policy=l34,socket_id=0,mac=$first_mac,$arr""
    else
	first_pci=`echo $arr | cut -d, -f1 | cut -d= -f2`

	if [ $(grep "physical_interface_address = " /etc/contrail/contrail-vrouter-agent.conf | wc -l) = 0 ]; then
            sed -i.bak '/\[SANDESH\]/i physical_interface_address = '$first_pci' ' /etc/contrail/contrail-vrouter-agent.conf
	else
	    sed -i.bak 's/^\(physical_interface_address = \).*/\1'$first_pci'/' /etc/contrail/contrail-vrouter-agent.conf
	fi
	
        sed -i.bak 's/^\(physical_interface = eth_bond0\).*/physical_interface = '$nic_arr'/' /etc/contrail/contrail-vrouter-agent.conf
	sed -i.bak 's/^\(dev=\).*/\1'$nic_arr'/' /etc/contrail/contrail-compute.conf
	
    fi

    ##################################
    # Sock options based on NUMA
    ##################################
    if [ `dmesg|grep -i NUMA|awk '{print $3$4}'` = "NoNUMA" ]; then 
        SOCK_ARGS="--socket-mem 1024"
    else
        SOCK_ARGS="--socket-mem 1024,1024"
    fi

    ##################################

    source /etc/contrail/contrail-compute.conf
    EXT_DEV=$dev
    if [ -e $VHOST_CFG ]; then
	source $VHOST_CFG
    else
	IPADDR=$(sudo ifconfig $EXT_DEV | sed -ne 's/.*inet [[addr]*]*[: ]*\([0-9.]*\).*/\1/i p')
        NETMASK=$(sudo ifconfig $EXT_DEV | sed -ne 's/.*[[net]*]*mask[: *]\([0-9.]*\).*/\1/i p')
    fi

    sudo sysctl -w net.core.wmem_max=9216000

    # don't die in small memory environments
    if [[ "$CONTRAIL_DEFAULT_INSTALL" != "True" ]]; then
	sudo taskset -c $CORE_MASK /usr/bin/contrail-vrouter-dpdk --no-daemon $VDEV_ARGS $SOCK_ARGS &
	sleep 15

        if [[ $? -eq 1 ]] ; then 
            exit 1
        fi
    else    
        sudo sh -c 'sync && echo 3 > /proc/sys/vm/drop_caches'

	sudo taskset -c $CORE_MASK /usr/bin/contrail-vrouter-dpdk --no-daemon $VDEV_ARGS $SOCK_ARGS &
	sleep 15

        if [[ $? -eq 1 ]] ; then 
            exit 1
        fi
    fi 

    configure_vrouter_dpdk
}

#######################################################################################
#### DON'T CHANGE THIS LINE: Above content shall be copied as it is to contrail.sh ####
#######################################################################################

CONTRAIL_DEFAULT_INSTALL=false
CONTRAIL_SRC=${CONTRAIL_SRC:-/opt/stack/contrail}
TARGET=${TARGET:-production}

echo "-----------------------RESTARTING VROUTER---------------------------"
ps -ef | grep 'contrail-vrouter-dpdk' | grep -v grep | awk '{print $2}' | xargs sudo kill
start_vrouter_dpdk
echo "-----------------------RESTARTING VROUTER FINISHED---------------------------"


