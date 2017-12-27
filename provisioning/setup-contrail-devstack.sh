#!/usr/bin/env bash

export WORKSPACE=$PWD
export GIT_EMAIL=$1
export GIT_USERNAME=$2
export GIT_PASSWORD=$3
export DEVSTACK_BRANCH="stable/newton"
export phy_intf="eth1"


line_to_search_1="change_stage \"python-dependencies\" \"repo-init\""
line_to_add_1="cp $WORKSPACE/manifest.xml \$CONTRAIL_SRC/.repo/manifest.xml"

line_to_search_2="change_stage \"repo-sync\" \"fetch-packages\""
line_to_add_2="git clone https://github.com/Juniper/contrail-dpdk -b contrail_dpdk_2_1 \$CONTRAIL_SRC/third_party/dpdk; sed -i 's/snb/native/g' \$CONTRAIL_SRC/third_party/dpdk/config/defconfig_x86_64-native-linuxapp-gcc; grep -rl 'rcu_barrier' \$CONTRAIL_SRC/vrouter/ | xargs sed -i 's/rcu_barrier();/\\\/*rcu_barrier();*\\\/ \\\/* Deepak *\\\//g';"

line_to_search_3="function stop_contrail()"
line_to_add_3="#Deepak\n    ps -ef | grep 'contrail-vrouter-dpdk' | grep -v grep | awk '{print \$2}' | xargs sudo kill"

line_to_rep_orig_4="if is_service_enabled agent; then[ \t\r\n]*test_insert_vrouter"
line_to_rep_new_4="if is_service_enabled agent; then\n\t# Deepak\n\tif [ \$dpdk_enabled = true ] ; then\n\t    start_vrouter_dpdk\n\telse\n\t    test_insert_vrouter\n\tfi"

line_to_rep_orig_5="if \[\[ \"\$CONTRAIL_DEFAULT_INSTALL\" != \"True\" \]\]; then[ \t\r\n]*sudo \$CONTRAIL_SRC\/build\/\$TARGET\/vrouter\/utils\/vif --create \$CONTRAIL_VGW_INTERFACE --mac 00:00:5e:00:01:00[ \t\r\n]*else[ \t\r\n]*sudo \/usr\/bin\/vif --create \$CONTRAIL_VGW_INTERFACE --mac 00:00:5e:00:01:00[ \t\r\n]*fi[ \t\r\n]*sudo ifconfig \$CONTRAIL_VGW_INTERFACE up[ \t\r\n]*sudo route add -net \$CONTRAIL_VGW_PUBLIC_SUBNET dev \$CONTRAIL_VGW_INTERFACE"
line_to_rep_new_5="#Deepak\n\tif \[ \$dpdk_enabled = false \] ; then\n\t    if \[\[ \"\$CONTRAIL_DEFAULT_INSTALL\" != \"True\" \]\]; then\n\t\tsudo \$CONTRAIL_SRC\/build\/\$TARGET\/vrouter\/utils\/vif --create \$CONTRAIL_VGW_INTERFACE --mac 00:00:5e:00:01:00\n\t    else\n\t\tsudo \/usr\/bin\/vif --create \$CONTRAIL_VGW_INTERFACE --mac 00:00:5e:00:01:00\n\t    fi\n\t    sudo ifconfig \$CONTRAIL_VGW_INTERFACE up\n\t    sudo route add -net \$CONTRAIL_VGW_PUBLIC_SUBNET dev \$CONTRAIL_VGW_INTERFACE\n\tfi"

line_to_rep_orig_6="fi[ \t\r\n]*# restore saved screen settings[ \t\r\n]*SCREEN_NAME=\$SAVED_SCREEN_NAME[ \t\r\n]*return[ \t\r\n]*}[ \t\r\n]*function configure_contrail() {"
line_to_rep_new_6="fi\n\n    # Deepak\n    if [ \$dpdk_enabled = true ] ; then\n\tif is_service_enabled agent; then\n\t    restart_intf_vrouter_dpdk\n\tfi\n    fi\n\n    # restore saved screen settings\n    SCREEN_NAME=\$SAVED_SCREEN_NAME\n    return\n}\n\nfunction configure_contrail() {"

line_to_rep_orig_7="apt_get install chkconfig"
line_to_rep_new_7="apt_get install sysv-rc-conf"

dpdk_enabled=false
#while true; do
#    read -p "Do you wish to install DPDK based vrouter?" yn
#    case $yn in
#        [Yy]* ) dpdk_enabled=true; break;;
#        [Nn]* ) dpdk_enabled=false; break;;
#        * ) echo "Please answer yes or no.";;
#    esac
#done

echo "******************************************************"
echo "Contrail-installer : Configure SSH keys for github"
echo "******************************************************"
echo "Check for existing ssh keys...."
keys_count=$(ls -al ~/.ssh | grep id_rsa | wc -l)
if [ $keys_count = 0 ]
then
    echo "No existing ssh keys found....Generating a new ssh key...."
    ssh-keygen -t rsa -b 4096 -f $WORKSPACE/.ssh/id_rsa -N "" -P "" -C $GIT_EMAIL
else
    echo "Existing ssh key found....Reusing..."
fi

eval $(ssh-agent -s)
ssh-add $WORKSPACE/.ssh/id_rsa

echo "Registering SSH-key to github:"
#cat $WORKSPACE/.ssh/id_rsa.pub

curl -u "$GIT_USERNAME:$GIT_PASSWORD" \
    --data "{\"title\":\"VagrantContrailDevstackVm_`date +%Y%m%d%H%M%S`\",\"key\":\"`cat $WORKSPACE/.ssh/id_rsa.pub`\"}" \
    https://api.github.com/user/keys


#read -p "Please add above ssh-key to your github account. Press y to continue or n to abort [y/n] : " yn
#case $yn in
#    [Nn]* ) echo "SSH key not registered to github account...Aborting...."; exit;;
#esac

ssh -T -o StrictHostKeyChecking=no git@github.com

echo "*************************************************"
echo "Contrail-installer : Installing the required Packages"
echo "*************************************************"
# Steps to install and configure devstack
sudo apt-get update 
sudo apt-get -y install git vim-gtk libxml2-dev libxslt1-dev libpq-dev python-pip libsqlite3-dev 
sudo apt-get -y build-dep python-mysqldb 
sudo pip install git-review tox 

git config --global user.email $GIT_EMAIL
git config --global user.name $GIT_USERNAME
git config --global user.editor "vim"

#sudo groupadd stack
#sudo useradd -g stack -s /bin/bash -d /opt/stack -m stack
#echo "stack ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/stack
#sudo su - stack

echo "******************************************************************************"
echo "Contrail-installer : Checkout contrail-installer and devstack repositories"
echo "******************************************************************************"

git clone https://github.com/juniper/contrail-installer.git
git clone https://github.com/openstack-dev/devstack -b $DEVSTACK_BRANCH
sudo chown -R vagrant:vagrant $WORKSPACE/devstack

cd $WORKSPACE/contrail-installer

#git reset --hard 74a95840e4f95086f0fde5e9ea575df36254deef

cp samples/localrc-all localrc

sed -i "/PHYSICAL_INTERFACE.*/s/.*/PHYSICAL_INTERFACE=$phy_intf/" localrc
#sed -i "/$line_to_search_1/a$line_to_add_1" $WORKSPACE/contrail-installer/contrail.sh

if [ $dpdk_enabled = true ]; then
    sudo apt-get install -y liburcu-dev
    
    if [ $(grep "\--dpdk-enabled True" $WORKSPACE/contrail-installer/contrail.sh | wc -l) = 0 ]; then
        sed -i 's/provision_vrouter.py/provision_vrouter.py --dpdk-enabled/g' $WORKSPACE/contrail-installer/contrail.sh
    fi

    sed -i "/$line_to_search_2/a$line_to_add_2" $WORKSPACE/contrail-installer/contrail.sh
    sed -i "/$line_to_search_3/a$line_to_add_3" $WORKSPACE/contrail-installer/contrail.sh

    ########################################################
    # Copy code to start and configure "DPDK based vRouter"
    # in contrail.sh
    ########################################################
    temp_str=`grep -n "Above content shall be copied as it is to contrail.sh" $WORKSPACE/restart_vrouter_dpdk.sh | awk '{print $1}'`
    lines_to_copy=${temp_str%%:#*}
    ((lines_to_copy=$lines_to_copy-1))
    cp $WORKSPACE/restart_vrouter_dpdk.sh $WORKSPACE/contrail-installer/
    sed -i 1r<(head -$lines_to_copy $WORKSPACE/contrail-installer/restart_vrouter_dpdk.sh) $WORKSPACE/contrail-installer/contrail.sh

    sed -n "1h;2,\$H;\${g;s/$line_to_rep_orig_4/$line_to_rep_new_4/;p}" $WORKSPACE/contrail-installer/contrail.sh > $WORKSPACE/contrail-installer/contrail_1.sh

    sed -n "1h;2,\$H;\${g;s/$line_to_rep_orig_5/$line_to_rep_new_5/;p}" $WORKSPACE/contrail-installer/contrail_1.sh > $WORKSPACE/contrail-installer/contrail_2.sh

    sed -n "1h;2,\$H;\${g;s/$line_to_rep_orig_6/$line_to_rep_new_6/;p}" $WORKSPACE/contrail-installer/contrail_2.sh > $WORKSPACE/contrail-installer/contrail.sh

    rm -rf $WORKSPACE/contrail-installer/contrail_?.sh

fi

if [ $(grep "dpdk_enabled=" $WORKSPACE/contrail-installer/localrc | wc -l) = 0 ]; then
    echo "dpdk_enabled=$dpdk_enabled" >> $WORKSPACE/contrail-installer/localrc
fi

# Workaround - package not available in Ubuntu
sed -n "1h;2,\$H;\${g;s/$line_to_rep_orig_7/$line_to_rep_new_7/;p}" $WORKSPACE/contrail-installer/contrail.sh > $WORKSPACE/contrail-installer/contrail_1.sh
mv $WORKSPACE/contrail-installer/contrail_1.sh $WORKSPACE/contrail-installer/contrail.sh

# TODO:remove following packages - libipfix-dev, python-docker-py, python-sseclient

chmod +x $WORKSPACE/contrail-installer/contrail.sh

#./contrail.sh build
#./contrail.sh install
#./contrail.sh configure
#./contrail.sh start

./contrail.sh

sleep 10

########################################################
# proceed for devstack setup
########################################################
cd $WORKSPACE/devstack

cp $WORKSPACE/contrail-installer/devstack/lib/neutron_plugins/opencontrail $WORKSPACE/devstack/lib/neutron_plugins/
cp $WORKSPACE/contrail-installer/devstack/samples/localrc-all $WORKSPACE/devstack/localrc

########################################################
# Update devstack/localrc
########################################################
source /etc/contrail/contrail-compute.conf
EXT_DEV=$dev
if [ -e $VHOST_CFG ]; then
    source $VHOST_CFG
else
    DEVICE=vhost0
    IPADDR=$(sudo ifconfig $EXT_DEV | sed -ne 's/.*inet [[addr]*]*[: ]*\([0-9.]*\).*/\1/i p')
    NETMASK=$(sudo ifconfig $EXT_DEV | sed -ne 's/.*[[net]*]*mask[: *]\([0-9.]*\).*/\1/i p')
fi

sed -i "/PHYSICAL_INTERFACE.*/s/.*/PHYSICAL_INTERFACE=$phy_intf/" $WORKSPACE/devstack/localrc
echo "NOVNC_BRANCH=v0.6.0" >> $WORKSPACE/devstack/localrc
echo "HOST_IP=$IPADDR" >> $WORKSPACE/devstack/localrc

########################################################
# Update ~/.bashrc
########################################################
echo "export CONTRAIL_DIR=$WORKSPACE/contrail-installer" >> ~/.bashrc
echo "export DEVSTACK_DIR=$WORKSPACE/devstack" >> ~/.bashrc

echo "export no_proxy=127.0.0.1,localhost,$IPADDR" >> ~/.bashrc

# COMMON OPENSTACK ENVS
echo "export OS_USERNAME=admin" >> ~/.bashrc
echo "export OS_PASSWORD=contrail123" >> ~/.bashrc
echo "export OS_TENANT_NAME=admin" >> ~/.bashrc
echo "export OS_AUTH_URL=http://$IPADDR:5000/v2.0" >> ~/.bashrc
echo "export OS_AUTH_STRATEGY=keystone" >> ~/.bashrc
echo "export OS_NO_CACHE=1" >> ~/.bashrc
echo "export OS_AUTH_URL=http://$IPADDR:5000/v2.0" >> ~/.bashrc
echo "export OS_IDENTITY_API_VERSION=2.0" >> ~/.bashrc

# LEGACY NOVA ENVS
echo "export NOVA_USERNAME=\${OS_USERNAME}" >> ~/.bashrc
echo "export NOVA_PROJECT_ID=\${OS_TENANT_NAME}" >> ~/.bashrc
echo "export NOVA_PASSWORD=\${OS_PASSWORD}" >> ~/.bashrc
echo "export NOVA_API_KEY=\${OS_PASSWORD}" >> ~/.bashrc
echo "export NOVA_URL=\${OS_AUTH_URL}" >> ~/.bashrc
echo "export NOVA_VERSION=1.1" >> ~/.bashrc
echo "export NOVA_REGION_NAME=RegionOne" >> ~/.bashrc

# Replace git.openstack.org with https://github.com/openstack in "GIT_BASE=${GIT_BASE:-git://git.openstack.org}"
str_to_rep_old="git\:\/\/git.openstack.org"
str_to_rep_new="https\:\/\/git.openstack.org"

sed -n "1h;2,\$H;\${g;s/$str_to_rep_old/$str_to_rep_new/;p}" $WORKSPACE/devstack/stackrc > $WORKSPACE/devstack/stackrc_new
mv $WORKSPACE/devstack/stackrc_new $WORKSPACE/devstack/stackrc

sudo chown -R vagrant:vagrant $WORKSPACE/devstack

FORCE=yes ./stack.sh
