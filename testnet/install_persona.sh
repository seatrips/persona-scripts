#!/bin/bash

#set -x

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
#                                                     #
#               Persona Commander Script              #
# 	          developed by tharude 	              #
#		a.k.a The Forging Penguin	      #
#         thanks ViperTKD for the helping hand        #
#                 19/01/2017 ARK Team                 #
#         and modified for Persona by                 #
#               SuperGrobi2.0                         #
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

LOC_SERVER="http://127.0.0.1"

pause(){
        read -p "   	Press [Enter] key to continue..." fakeEnterKey
}

persona_enviroment="testnet"
personash_loc="https://raw.githubusercontent.com/supergrobi020/persona-scripts/master/persona.sh"


#PSQL Queries
query() {
    PUBKEY="$(psql -d persona_testnet -t -c 'SELECT ENCODE("publicKey",'"'"'hex'"'"') as "publicKey" FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    DNAME="$(psql -d persona_testnet -t -c 'SELECT username FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    PROD_BLOCKS="$(psql -d persona_testnet -t -c 'SELECT producedblocks FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    MISS_BLOCKS="$(psql -d persona_testnet -t -c 'SELECT missedblocks FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    #BALANCE="$(psql -d persona_testnet -t -c 'SELECT (balance/100000000.0) as balance FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | sed -e 's/^[[:space:]]*//')"
    BALANCE="$(psql -d persona_testnet -t -c 'SELECT to_char(("balance"/100000000.0), '"'FM 999,999,999,990D00000000'"' ) as balance FROM mem_accounts WHERE "address" = '"'"$ADDRESS"'"' ;' | xargs)"
    HEIGHT="$(psql -d persona_testnet -t -c 'SELECT height FROM blocks ORDER BY HEIGHT DESC LIMIT 1;' | xargs)"
    RANK="$(psql -d persona_testnet -t -c 'WITH RANK AS (SELECT DISTINCT "publicKey", "vote", "round", row_number() over (order by "vote" desc nulls last) as "rownum" FROM mem_delegates where "round" = (select max("round") from mem_delegates) ORDER BY "vote" DESC) SELECT "rownum" FROM RANK WHERE "publicKey" = '"'03cfafb2ca8cf7ce70f848456b1950dc7901946f93908e4533aace997c242ced8a'"';' | xargs)"
}

function net_height {
    local heights=$(curl -s "$LOC_SERVER/api/peers" | jq -r '.peers[] | .height')
    
    highest=$(echo "${heights[*]}" | sort -nr | head -n1)
}

function proc_vars {
        node=`pgrep -a "node" | grep persona-node | awk '{print $1}'`
        if [ "$node" == "" ] ; then
                node=0
        fi

        # Is Postgres running
        pgres=`pgrep -a "postgres" | awk '{print $1}'`

        # Find if forever process manager is runing
        frvr=`pgrep -a "node" | grep forever | awk '{print $1}'`

        # Find the top level process of node
        #top_lvl=$(top_level_parent_pid $node)

        # Looking for ark-node installations and performing actions
        personadir=$(locate -b 'persona-node')

        # Getting the parent of the install path
        parent=`dirname $personadir 2>&1`

        # Forever Process ID
        forever_process=`forever --plain list | grep $node | sed -nr 's/.*\[(.*)\].*/\1/p'`

        # Node process work directory
        nwd=`pwdx $node 2>/dev/null | awk '{print $2}'`
}


# Drop ARK DB
function drop_db {
        # check if it's running and start if not.
        if [ -z "$pgres" ]; then
                sudo service postgresql start
        fi
        echo -e "\n[Info]\t✔ Droping the persona database!"
        dropdb --if-exists persona_testnet
}

function create_db {
        #check if PG is running here if not Start.
        if [ -z "$pgres" ]; then
                sudo service postgresql start
        fi
        echo -e "\n[Info]\t✔ Creating the persona database!"
        sudo -u postgres psql -c "update pg_database set encoding = 6, datcollate = 'en_US.UTF8', datctype = 'en_US.UTF8' where datname = 'template0';"
        sudo -u postgres psql -c "update pg_database set encoding = 6, datcollate = 'en_US.UTF8', datctype = 'en_US.UTF8' where datname = 'template1';"
        sudo -u postgres dropuser --if-exists $USER
        sudo -u postgres psql -c "CREATE USER $USER WITH PASSWORD 'password' CREATEDB;"
        createdb persona_testnet
}

function promptyn () {
    while true; do
        read -p "$1 " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo -e "\n[Info]Please answer yes or no.\n[Info]";;
        esac
    done
}

# Check if program is installed
function node_check {
        # defaulting to 1
        return_=1
        # changing to 0 if not found
        type $1 >/dev/null 2>&1 || { return_=0; }
        # return value
        # echo "$return_"
}

function os_up {
    echo -e "Checking for system updates...\n[Info]"
    sudo apt-get update >&- 2>&-
    avail_upd=`/usr/lib/update-notifier/apt-check 2>&1 | cut -d ';' -f 1`
        if [ "$avail_upd" == 0 ]; then
                echo -e "There are no updates available\n[Info]"
                sleep 1
        else
	     if promptyn "There are $avail_upd updates available for your system. Would you like to install them now? [y/N]: "; then
            echo -e "Updating the system...\n[Info]"

            sudo apt-get upgrade -yqq
            sudo apt-get dist-upgrade -yq
            
			echo -e "Do some cleanup..."

			sudo apt-get autoremove -yyq
            sudo apt-get autoclean -yq
            
			echo -e "\n[Info]The system was updated!"
            echo -e "\n[Info]System restart is recommended!"
            
         else
            echo -e "\n[Info]System update canceled. We strongly recommend that you update your operating system on a regular basis."
         fi
        fi
}

function check_dependencies()
{
    local -a dependencies="postgresql postgresql-contrib libpq-dev build-essential python git curl jq libtool autoconf locales automake locate zip unzip htop nmon iftop pkg-config libcairo2-dev libgif-dev ntp"

    DEPS_TO_INSTALL=""
    for dependency in ${dependencies[@]}; do
        PKG_INSTALLED=$(dpkg -l "$dependency" 2>/dev/null | fgrep "$dependency" | egrep "^[a-zA-Z]" | awk '{print $2}') || true
        if [[ "$PKG_INSTALLED" != "$dependency" ]]; then
            DEPS_TO_INSTALL="$DEPS_TO_INSTALL$dependency "
        fi
    done

    if [[ ! -z "$DEPS_TO_INSTALL" ]]; then
	     if promptyn "Dependencies [ ${DEPS_TO_INSTALL}] are not installed. Do you want to install them? [y/N]: "; then
            echo -e "Installing Program Dependencies...\n[Info]"
            sudo sh -c "sudo apt-get install ${DEPS_TO_INSTALL}"
            echo -e "Program Dependencies Installed!\n[Info]"
         else
            echo -e "\n[Info]Please ensure that the following packages are installed and try again:\n[Info]${DEPS_TO_INSTALL}"
         fi
	fi
}

# Install Node Version Manager (NVM)
function nvm {
        node_check node
        if [ "$return_" == 0 ]; then
                echo -e "\n[Info]Node is not installed, installing..."
                curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.32.0/install.sh 2>/dev/null | bash >>install.log
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

                ### Installing node ###
                nvm install 8.9.4 >>install.log
                nvm use 8.9.4 >>install.log
                nvm alias default 8.9.4 >>install.log
		npm install -g npm >>install.log 2>&1
                echo -e "\n[Info]Node `node -v` has been installed."
        else
                echo -e "\n[Info]Node `node -v` is  already installed."
        fi

        node_check forever
        if [ "$return_" == 0 ]; then
                echo -e "\n[Info]Forever is not installed, installing..."
                ### Install forever ###
                sudo npm install forever -g >>install.log 2>&1
                echo -e "\n[Info]Forever has been installed."
        else
                echo -e "\n[Info]Forever is alredy installed."
        fi
        # Setting fs.notify.max_user_watches
        if grep -qi 'fs.inotify' /etc/sysctl.conf ; then
                echo -e "\n[Info]fs.inotify.max_user_watches is already set."
        else
                echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf && sudo sysctl -p
        fi
        echo -e "\n[Info]Check install.log for reported install errors."
}




# Update Persona node
update_persona(){

    proc_vars
    check_dependencies

    #Stop persona node
    if [[ ${frvr} ]]; then
        echo -e "\n[Info]Stopping Persona process: ${frvr}"
        $personadir/persona.sh stop
    fi
	
	# Backup persona-node config
	cp $personadir/config.${persona_enviroment}.json $HOME
	
	if [[ -d ${HOME}/personaBackup.old ]]; then
		echo -e "\n[Info]Removing the old backup directory: ${personadir}/personaBackup.old"
		rm -fr ${HOME}/personaBackup.old
	fi
	echo -e "\n[Info]Creating a backup of the node directory: ${personadir}"
	mv $personadir personaBackup.old
        cd $HOME
    
    
    nvm

	echo -e "\n[Info]Cloaning and installing the Persona node.\n"
        git clone https://github.com/PersonaIam/persona${persona_enviroment} persona-node
        cd persona-node
        npm install libpq 2>/dev/null
        npm install secp256k1 2>/dev/null
        npm install bindings 2>/dev/null
        npm install 2>/dev/null
	
	
	echo -e "\n[Info]Downloading the Persona manager."
        wget -q ${personash_loc}
	chmod u+x $personadir/persona.sh
        echo -e "\n[Info]Drink a beer. We need up upgrade the file system database. This is making us faster."
        sudo updatedb

}

#Install Persona Node
inst_persona(){
	proc_vars
	cd $HOME
	if [[ ${frvr} ]]; then
		echo -e "\n[Info]Stopping Persona process: ${frvr}"
		$personadir/persona.sh stop
		echo -e "\n[Info]Dropping the Persona database"
		drop_db
	fi
	
    create_db
	update_persona

	echo -e "\n[Info]Copy the old configuration file back to: ${personadir}"
	cp $HOME/config.${persona_enviroment}.json $personadir
	$personadir/persona.sh start 	

}

case $1 in
    "install")
      inst_persona
    ;;
    "os_update")
      os_up
      ;;
    "update")
      update_persona
    ;;
*)
    echo 'Available options: install, update, os_update'
    echo "Usage: ${0}"
    exit 1
    ;;
esac
exit 0
