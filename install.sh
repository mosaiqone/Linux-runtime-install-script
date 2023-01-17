#!/bin/bash
set -eu

################################################################################
# Parameters
################################################################################
readonly NUPANO_DOCKER_COMPOSE_FILE_URL=https://raw.githubusercontent.com/mosaiqone/Linux-runtime-install-script/main/docker-compose.yml

# Color Definitions
readonly RED='\e[1;31m'
readonly GREEN='\e[1;32m'
readonly CYAN='\e[1;36m'
readonly ORANGE='\e[1;33m'
readonly NC='\e[0m'




################################################################################
# Function Definition
################################################################################
check_root_priviliges() {
    if [ "$EUID" -eq 0 ] && [ -z ${SUDO_USER:+set} ] ; then
        readonly SCRIPT_USER=root
        readonly SCRIPT_USER_HOME=/root
        return
    fi

    if [ -z ${SUDO_USER:+set} ] ; then
        printf "${RED}Please start the script with root user rights, e.g. by using sudo.${NC}\n" >&2
        exit 1
    fi
    readonly SCRIPT_USER=$SUDO_USER
    readonly SCRIPT_USER_HOME=/home/${SCRIPT_USER}
}

check_runtime_version_given() {
    if [[ $# -lt 1 ]]; then
      log_failure "Please provide a Runtime version string or use 'latest'"
      exit 1
    fi
    readonly NUPANO_RUNTIME_VERSION=$1    
}

create_nupano_folder() {
    readonly NUPANO_FOLDER=${SCRIPT_USER_HOME}/.nupano
    mkdir -p "$NUPANO_FOLDER"
    chown -R "$SCRIPT_USER" "$NUPANO_FOLDER"
}


welcome_message() {
    clear
    log_message "\n${CYAN}"
    log_message " 888b    889 888     888 8888888b.     d8888 888b    888  .d88888b.  \n"
    log_message " 8888b   888 888     888 888   Y88b   d88888 8888b   888 d88P' 'Y88b \n"
    log_message " 88888b  888 888     888 888    888  d88P888 88888b  888 888     888 \n"
    log_message " 888Y88b 888 888     888 888   d88P d88P 888 888Y88b 888 888     888 \n"
    log_message " 888 Y88b888 888     888 8888888P' d88P  888 888 Y88b888 888     888 \n"
    log_message " 888  Y88888 888     888 888      d88P   888 888  Y88888 888     888 \n"
    log_message " 888   Y8888 Y88b. .d88P 888     d8888888888 888   Y8888 Y88b. .d88P \n"
    log_message " 888    Y888  'Y88888P'  888    d88P     888 888    Y888  'Y88888P'  \n"
    log_message "   ___            __  _             ____         __       ____       \n"
    log_message "  / _ \__ _____  / /_(_)_ _  ___   /  _/__  ___ / /____ _/ / /__ ____\n"
    log_message " / , _/ // / _ \/ __/ /  ' \/ -_) _/ // _ \(_-</ __/ _  / / / -_) __/\n"
    log_message "/_/|_|\_,_/_//_/\__/_/_/_/_/\__/ /___/_//_/___/\__/\_,_/_/_/\__/_/   \n"
    log_message "${NC}\n\n"
}


ensure_dependencies() {
    log_headline "Installing required dependencies"
    ensure_dependency "wget" "wget --version"
}

ensure_dependency() {
    local -r NAME=$1
    local -r TEST_CMD=$2

    log_message "Check if ${CYAN}$NAME${NC} is installed…\n"
    if $TEST_CMD &>/dev/null ; then
        log_success installed
    else
        log_warning "not installed"
        log_message "${CYAN}Install $NAME now…${NC}\n"
        apt-get -y -q install $NAME 2>&1 | tee -a $LOG_FILE
        if [ ${PIPESTATUS[0]} -ne 0 ] ; then
            log_failure "Could not install '$NAME'. Exit script…"
            exit 1
        fi
        log_success "installation of ${NAME} finished"
    fi
}

uninstall_docker() {
    #source: https://docs.docker.com/engine/install/ubuntu/
    log_headline "Uninstalling previously installed Docker version"
    log_message "Initiate uninstall of docker..." 
    #apt-get -q -y remove docker docker-engine docker.io containerd runc || true
    #call each command inividually to ensure continuation in case a removal fails (e.g. because the software was not installed)
    apt-get -q -y remove docker || true
    apt-get -q -y remove docker-engine || true
    apt-get -q -y remove docker.io || true
    apt-get -q -y remove containerd || true
    apt-get -q -y remove runc || true

    if [ $? -ne 0 ] ; then
        log_failure "Uninstall of old docker versions. Aborting Runtime installation…"
    fi

    log_success "Uninstalling of Docker done"
}

install_docker() {
    #source: https://docs.docker.com/engine/install/ubuntu/

    log_headline "Install Docker and Docker Compose"
    log_message "Update and install required tools"
    apt-get -q -y update
    apt-get -q -y install ca-certificates curl gnupg lsb-release

    if [ $? -ne 0 ] ; then
        log_failure "Update and install of required tools failed. Aborting Runtime installation…"
    fi

    log_success "Update and installation required tools done"

    log_message "Initiate docker installation…" 
    log_message "Add Docker's official GPG key"
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    log_message "setup Docker repository"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_message "Install Docker Engine and Docker compose"
    chmod a+r /etc/apt/keyrings/docker.gpg
    apt-get -q -y update
    
    apt-get -q -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin

    if [ $? -ne 0 ] ; then
        log_failure "Docker Engine and Docker compose installation failed. Aborting Runtime installation…"
    fi

    log_success "Docker installation done"
}


get_checked_user_input() {
    local -r PROMPT=$1
    local -r CHECK_REGEX=$2
    local -r RETURN_VALUE_NAME=$3
    while true; do
        read -p "$PROMPT" input_value
        if [[ $input_value =~ $CHECK_REGEX ]]; then
            break
        fi
        log_message_safe "Invalid user input, please enter a value that applies to this regex: '$CHECK_REGEX'"
    done
    declare -g "$RETURN_VALUE_NAME"="$input_value"
}


evaluate_yes_no_answer() {
    local -r PROMPT=$1
    local -r DEFAULT=$2

    while true ; do
        read -p "$PROMPT " answer

        # use default on empty answer
        if [ -z ${answer:+set} ] ; then
            answer=$DEFAULT
        fi

        answer=$(trim "$answer")
        answer=$(make_lowercase "$answer")

        if [ "$answer" = 'y' ] || [ "$answer" == "yes" ] ; then
            return 0
        fi

        if [ "$answer" = 'n' ] || [ "$answer" = "no" ] ; then
            return 1
        fi

        printf "${RED} -> Invalid answer, please enter 'yes' or 'no'!${NC}\n" >&2
    done
}

trim() {
    echo $(echo "$1" | xargs -0)
}

make_lowercase() {
    echo $(echo "$1" | tr '[:upper:]' '[:lower:]')
}


get_docker_compose_file() {
    wget -O "${NUPANO_FOLDER}/docker-compose.yml" "${NUPANO_DOCKER_COMPOSE_FILE_URL}"
}

modify_docker_compose_file() {
    log_headline "Configuring the Runtime..."
    readonly DOCKER_COMPOSE_FILE_PATH="${NUPANO_FOLDER}/docker-compose.yml"

    local HARDWARE_MANUFACTURER=""
    local HARDWARE_MANUFACTURER_URL=""
    local HARDWARE_MODEL_NAME=""
    local HARDWARE_SERIAL_NUMBER=""

    if evaluate_yes_no_answer "Do you want to use default parameters? (Yes/no)" "y"; then
        HARDWARE_MANUFACTURER="N/A"
        HARDWARE_MANUFACTURER_URL="N/A"
        HARDWARE_MODEL_NAME="Generic PC"
        HARDWARE_SERIAL_NUMBER=""
    else
        log_message "Please provide information about the hardware which hosts the NUPANO Runtime:\n"
        local -r NAME_REGEX='^[A-Za-z0-9\ _\.-]+$'
        while true; do
            get_checked_user_input "Please enter the hardware manufacturer name: " \
                "$NAME_REGEX" \
                "hardwareManufacturer"

            get_checked_user_input "Please enter the hardware manufacturer URL: " \
                '[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]' \
                "hardwareManufacturerUrl"

            get_checked_user_input "Please enter the hardware model name: " \
                "$NAME_REGEX" \
                "hardwareModelName"

            get_checked_user_input "Please enter the hardware serial number: " \
                "$NAME_REGEX" \
                "hardwareSerialNumber"

            log_message "\nThe NUPANO Runtime parameters are:\n" 
            log_message_safe "Manufacturer name: '${hardwareManufacturer}'"
            log_message_safe "Manufacturer URL: '${hardwareManufacturerUrl}'"
            log_message_safe "Model name: '${hardwareModelName}'"
            log_message_safe "Serial number: '${hardwareSerialNumber}'"
            
            if evaluate_yes_no_answer "Are you sure that the entered inputs are correct? (Yes/no)" "y"; then
                HARDWARE_MANUFACTURER="$hardwareManufacturer"
                HARDWARE_MANUFACTURER_URL="$hardwareManufacturerUrl"
                HARDWARE_MODEL_NAME="$hardwareModelName"
                HARDWARE_SERIAL_NUMBER="$hardwareSerialNumber"
                break
            fi
        done
    fi

    log_message "Modifying the Docker-Comnpose file..."
    #set Runtime image version
    sed -i -e "s/:latest/:'${NUPANO_RUNTIME_VERSION}'/g" docker-compose.yml
    
    #set environmental variable
    sed -i -e "s/nupano.description.manufacturer=not specified/nupano.description.manufacturer='${HARDWARE_MANUFACTURER}'/g" docker-compose.yml
    sed -i -e "s/nupano.description.manufacturer-url=not specified/nupano.description.manufacturer='${HARDWARE_MANUFACTURER_URL}'/g" docker-compose.yml
    sed -i -e "s/nupano.description.model-name=Generic PC/nupano.description.manufacturer='${HARDWARE_MODEL_NAME}'/g" docker-compose.yml

    #special handling of serial number if not given, the UUID of the Runtime will be used
    if [ -z "${HARDWARE_SERIAL_NUMBER}" ]; then
        #serial number not given -> do nothing ->  UUID will be used
        sed -i -e "s/#- nupano.description.serial-number=/#- nupano.description.serial-number=/g" docker-compose.yml
    else
        #serial number given -> use data
        sed -i -e "s/#- nupano.description.serial-number=/- nupano.description.serial-number='${HARDWARE_SERIAL_NUMBER}'/g" docker-compose.yml
    fi

    log_success "Docker-compose file has been modified!"
}

start_nupano_runtime() {
    docker compose -f ${NUPANO_FOLDER}/docker-compose.yml up
}


################################################################################
# LOGGING Definitions
################################################################################

# only call once
create_log_file() {
    local -r DATE=$(date +"%Y-%m-%d_%H-%M-%S")
    local -r LOG_FOLDER=${NUPANO_FOLDER}/${DATE}_install-logs/
    readonly LOG_FILE=${LOG_FOLDER}logs.txt
    mkdir -p "$LOG_FOLDER"
    touch "$LOG_FILE"
    printf "\nInstallation logs for this script will be found under folder : ${LOG_FOLDER}\n\n"

    chown -R $SCRIPT_USER $NUPANO_FOLDER
}

log_message() {
    printf "$1"
    printf "$1" | sed -e 's/\x1b\[[0-9;]*m//g' >> $LOG_FILE 
}

log_message_safe() {
    printf '%s\n' "$1"
    printf '%s\n' "$1" | sed -e 's/\x1b\[[0-9;]*m//g' >> $LOG_FILE
}

log_headline() {
    local -r TEXT=$1
    local -r TEXT_LEN=${#1}
    local -r HEADLINE_LEN=$(($TEXT_LEN+4))
    local line=""
    for (( i=0; i<$HEADLINE_LEN; ++i )); do
        line="${line}#"
    done
    log_message "\n${CYAN}$line\n"
    log_message "# $TEXT #"
    log_message "\n$line${NC}\n"
}

log_success() {
    local text=success
    if [ ${1:+set} ]; then
        text=$(trim "$1")
    fi
    log_message " ${GREEN}-> ${text}${NC}\n"
}

log_failure() {
    local text=failure
    if [ ${1:+set} ]; then
        text=$(trim "$1")
    fi
    log_message " ${RED}-> ${text}${NC}\n"
}

log_warning() {
    local text=failure
    if [ ${1:+set} ]; then
        text=$(trim "$1")
    fi
    log_message " ${ORANGE}-> ${text}${NC}\n"
}

################################################################################
# Installation Script Sequence
################################################################################
check_root_priviliges
check_runtime_version_given "$1"
create_nupano_folder
create_log_file
log_message "16:46"
welcome_message
ensure_dependencies
#uninstall_docker
#install_docker
get_docker_compose_file
modify_docker_compose_file
#start_nupano_runtime

log_success "NUPANO RUNTIME INSTALLATION FINISHED!"