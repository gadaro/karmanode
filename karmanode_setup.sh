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
	read -p "  Karmanode outputs tx_hash: " KARMANODE_TX_HASH
	read -p "  Karmanode outputs idx: " KARMANODE_IDX
	read -p "  Karmanode user (Default ohmcoin): " KARMANODE_USER
	read -p "  Karmanode rpc user: " KARMANODE_RPC_USER
	read -p "  Karmanode rpc password: " KARMANODE_RPC_PASS

	if [ -z "$KARMANODE_GENKEY" ]; then
		echo "=> Information provided on Karmanode genkey is not correct."
		ERRORS=true
	fi
	if [ -z "$KARMANODE_TX_HASH" ]; then
		echo "=> Information provided on Karmanode outputs tx_hash is not correct."
		ERRORS=true
	fi
	if [ -z "$KARMANODE_IDX" ]; then
		echo "=> Information provided on Karmanode outputs idx is not correct."
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
	echo "Karmanode outputs tx_hash: $KARMANODE_TX_HASH"
	echo "Karmanode outputs idx: $KARMANODE_IDX"
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
	passwd $KARMANODE_USER
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
    	fallocate -l 2G /swapfile
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
    su -c "echo \"rpcuser=$KARMANODE_RPC_USER\" > ~/.ohmc/ohmc.conf" $KARMANODE_USER
    su -c "echo \"rpcpassword=$KARMANODE_RPC_PASS\" >> ~/.ohmc/ohmc.conf" $KARMANODE_USER

}

function installing_blockchain () {

    su -c "cd ~/.ohmc; wget http://www.ohmcoin.org/downloads/OHMC_Blockchain_snapshot.zip" $KARMANODE_USER
    su -c "cd ~/.ohmc; unzip OHMC_Blockchain_snapshot.zip" $KARMANODE_USER
    su -c "cd ~/.ohmc; rm OHMC_Blockchain_snapshot.zip" $KARMANODE_USER

}

gather_user_info
check_info

echo "--- Running system upgrade..."
system_upgrade

echo "--- Creating user $KARMANODE_USER..."
user_creation

echo "--- Disabling remote root login..."
modify_sshd_config

echo "--- Creating swap partition..."
create_swap_space

echo "--- Installing and configuring ohmc daemon..."
compile_ohm_daemon

echo "Installing blockchain snapshot..."
installing_blockchain

echo "Starting ohmc daemon..."

#cd ~/.ohmc
#ohmcd -daemon

echo "Waiting to daemon to get synced..."
