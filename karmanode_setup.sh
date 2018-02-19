#!/bin/bash
VERSION=1.0.0
DATE=`date +%F_%H%M%S`
if (( $EUID != 0 )); then
    echo "Please run as root"
    exit
fi

function gather_user_info () {

	clear

	ERRORS=false

	echo "| OHMC Karmanode configuration utility - ${VERSION}"
	echo "| Tested on ubuntu 16.04.3"
	echo "|--------------------------------------------------"
	echo ""
	read -p "  Karmanode genkey: " KARMANODE_GENKEY
	read -p "  Karmanode user (Default ohmcoin): " KARMANODE_USER
	read -s -p "  Karmanode password: " KARMANODE_PASS
	read -p "  Karmanode rpc user: " KARMANODE_RPC_USER
	read -p "  Karmanode rpc password: " KARMANODE_RPC_PASS

	if [ -z "$KARMANODE_GENKEY" ]; then
		echo "=> Information provided on Karmanode genkey is not correct."
		ERRORS=true
	fi
	if [ -z "$KARMANODE_RPC_USER" ]; then
		echo "=> Information provided on Karmanode rpc user is not correct."
		ERRORS=true
	fi
	if [ -z "$KARMANODE_RPC_PASS" ]; then
		echo "=> Information provided on Karmanode rpc password is not correct."
		ERRORS=true
	fi
	if [ -z "$KARMANODE_USER" ]; then
		echo "=> Using default: ohmcoin as Karmanode user."
		KARMANODE_USER=ohmcoin
	fi

	if [[ "$ERRORS" == "true" ]]; then
		echo "Please correct the above errors before continuing."
		exit
	fi
}

function check_info () {

	echo ""
	echo "Karmanode genkey: $KARMANODE_GENKEY"
	echo "Karmanode user: $KARMANODE_USER"
	echo "Karmanode rpc user: $KARMANODE_RPC_USER"
	echo "Karmanode rpc password: $KARMANODE_RPC_PASS"

	read -p "Procced? [y/n]: " PROCCED
	if [ "$PROCCED" != "y" ]; then
		echo "Aborted."
		exit
	fi
}

function system_upgrade () {

	add-apt-repository ppa:bitcoin/bitcoin -y
	apt-get -y update
	apt-get -y upgrade
	apt-get -y install pkg-config
	apt-get -y install build-essential autoconf automake libtool libboost-all-dev libgmp-dev libssl-dev libcurl4-openssl-dev git unzip wget
	apt-get -y install libdb4.8-dev libdb4.8++-dev

}

function user_creation () {

	useradd -m -U -s /bin/bash $KARMANODE_USER
    echo $KARMANODE_USER:$KARMANODE_PASS | chpasswd
	echo "Granting sudo privileges..."
	adduser $KARMANODE_USER sudo
    echo "Granting make without password..."
    echo '$KARMANODE_USER ALL = NOPASSWD: /usr/bin/make' | sudo EDITOR='tee -a' visudo

}

function modify_sshd_config () {

	if [ -f /etc/ssh/sshd_config ]; then
		cp /etc/ssh/sshd_config /etc/ssh/sshd_config_$DATE
		sed -re 's/^(\#)(PasswordAuthentication)([[:space:]]+)(.*)/\2\3\4/' -i /etc/ssh/sshd_config
		sed -re 's/^(\#?)(PasswordAuthentication)([[:space:]]+)yes/\2\3no/' -i /etc/ssh/sshd_config
		sed -re 's/^(\#)(UsePAM)([[:space:]]+)(.*)/\2\3\4/' -i /etc/ssh/sshd_config
		sed -re 's/^(\#?)(UsePAM)([[:space:]]+)yes/\2\3no/' -i /etc/ssh/sshd_config
		sed -re 's/^(\#)(PermitRootLogin)([[:space:]]+)(.*)/\2\3\4/' -i /etc/ssh/sshd_config
		sed -re 's/^(\#?)(PermitRootLogin)([[:space:]]+)(.*)/\2\3no/' -i /etc/ssh/sshd_config
	else
		echo "/etc/ssh/sshd_config does not exist, please review your ssh daemon configuration and try again. Aborting."
		exit
	fi

}

function create_swap_space () {

	if [ ! -f /swapfile ]; then
    	fallocate -l 3G /swapfile
		chmod 600 /swapfile
		mkswap /swapfile
		swapon /swapfile
		echo -e "/swapfile none swap sw 0 0 \n" >> /etc/fstab
	else
		echo "Swapfile already exists: `ls -l /swapfile`"	
	fi

}

function compile_ohm_daemon () {

    su -c "cd; git clone https://github.com/theohmproject/ohmcoin.git" $KARMANODE_USER
    su -c "cd ~/ohmcoin; chmod +x share/genbuild.sh; chmod +x autogen.sh" $KARMANODE_USER
    su -c "cd ~/ohmcoin; chmod 755 src/leveldb/build_detect_platform" $KARMANODE_USER
    su -c "cd ~/ohmcoin; ./autogen.sh" $KARMANODE_USER
    su -c "cd ~/ohmcoin; ./configure" $KARMANODE_USER
    su -c "cd ~/ohmcoin; sudo make" $KARMANODE_USER
    su -c "cd ~/ohmcoin; sudo make install" $KARMANODE_USER
    su -c "mkdir ~/.ohmc" $KARMANODE_USER
    su -c "echo rpcuser=$KARMANODE_RPC_USER > ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo rpcpassword=$KARMANODE_RPC_PASS >> ~/.ohmc/ohmc.conf" $KARMANODE_USER

}

function installing_blockchain () {

    su -c "cd ~/.ohmc; wget http://www.ohmcoin.org/downloads/OHMC_Blockchain_snapshot.zip" $KARMANODE_USER
    su -c "cd ~/.ohmc; unzip OHMC_Blockchain_snapshot.zip" $KARMANODE_USER
    su -c "cd ~/.ohmc; rm OHMC_Blockchain_snapshot.zip; rm -fR __MACOSX; rm OHMC/.DS_Store" $KARMANODE_USER
    su -c "cd ~/.ohmc; mv OHMC/* .; rm -fR OHMC" $KARMANODE_USER

}

function start_daemon () {

    su -c "cd ~/.ohmc; ohmcd -daemon" $KARMANODE_USER

}

function waiting_sync () {

    su -c "ohmc-cli getinfo | grep blocks" $KARMANODE_USE

}

function configure_daemon () {

    su -c "echo rpcallowip=127.0.0.1 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo staking=1 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo server=1 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo listen=1 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo daemon=1 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo logtimestamps=1 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo maxconnections=256 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo karmanode=1 | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo karmanodeprivkey=$KARMANODE_GENKEY | tee -a ~/.ohmc/ohmc.conf" $KARMANODE_USER

}

gather_user_info
check_info

echo ""
echo "--- Running system upgrade..."
echo ""
system_upgrade

echo ""
echo "--- Creating user $KARMANODE_USER..."
echo ""
user_creation

echo ""
echo "--- Disabling remote root login..."
echo ""
modify_sshd_config

echo ""
echo "--- Creating swap partition..."
echo ""
create_swap_space

echo ""
echo "--- Installing and configuring ohmc daemon..."
echo ""
compile_ohm_daemon

echo ""
echo "--- Installing blockchain snapshot..."
echo ""
installing_blockchain

echo ""
echo "--- Starting ohmc daemon..."
echo ""
start_daemon

echo ""
echo "--- Please wait daemon to get synced..."
echo ""
SYNCED=n
while [ $SYNCED == "n" ]; do
    waiting_sync
    read -p "It is the daemon synced? [y/n]: " SYNCED
done
echo "Daemon synced"

echo ""
echo "--- Applying following daemon configuration..."
echo ""
configure_daemon

echo ""
echo "--- Karmanode setup finished, system is going to be restarted in one minute"
echo "--- Remember to restart the daemon with the following command on user $KARMANODE_USER"
echo "--- cd ~/.ohmc; ohmcd -daemon"
echo ""
shutdown -r +1
