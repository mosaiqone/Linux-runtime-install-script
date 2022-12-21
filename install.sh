#!/bin/bash
set -eu

#call: $ sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/mosaiqone/Linux-runtime-install-script/main/install.sh) latest" root

################################################################################
# Parameters
################################################################################
readonly NUPANO_RUNTIME_DOCKER_IMAGE_NAME=public.ecr.aws/d9n0g1v8/nupano-runtime
readonly NUPANO_RUNTIME_DISCOVERY_DOCKER_IMAGE_NAME=public.ecr.aws/d9n0g1v8/nupano-runtime-discovery
readonly NUPANO_RUNTIME_UPDATER_DOCKER_IMAGE_NAME=public.ecr.aws/d9n0g1v8/nupano-runtime-updater

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

install_docker() {
    log_headline "Install Docker"
    log_message "Initiate docker installation…" 
    apt-get install -q -y docker.io
    if [ $? -ne 0 ] ; then
        log_failure "Docker installation failed. Aborting runtime installation…"
    fi

    log_success "docker installation done"
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


create_docker_compose_file() {
    log_headline "Configuring the Runtime..."

    readonly DOCKER_COMPOSE_FILE_PATH="${NUPANO_FOLDER}/docker-compose.yml"

    local COMMENT_IF_UUID_IS_USED=""

    if evaluate_yes_no_answer "Do you want to use default parameters? (Yes/no)" "n"; then
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
                break
            fi
        done
    else
        "${hardwareManufacturer}"="N/A"
        "${hardwareManufacturerUrl}"="N/A"
        "${hardwareModelName}"="Generic PC"
        "${hardwareSerialNumber}"=""
    fi

    readonly HARDWARE_MANUFACTURER="$hardwareManufacturer"
    readonly HARDWARE_MANUFACTURER_URL="$hardwareManufacturerUrl"
    readonly HARDWARE_MODEL_NAME="$hardwareModelName"
    readonly HARDWARE_SERIAL_NUMBER="$hardwareSerialNumber"

    if [ -z "$hardwareSerialNumber" ] then
        COMMENT_IF_UUID_IS_USED="#"
    else
        COMMENT_IF_UUID_IS_USED=""
    fi


    log_message "Creating the Docker-Comnpose file..."
    echo "
    version: '3.3'

    services:

      nupano-runtime:
        user: root #required for windows to access docker.sock
        restart: always
        image: ${NUPANO_RUNTIME_DOCKER_IMAGE_NAME}:${NUPANO_RUNTIME_VERSION}
        environment:
          - logging.level.com.nupano=INFO #INFO, DEBUG or TRACE
          - nupano.description.manufacturer=${HARDWARE_MANUFACTURER}
          - nupano.description.manufacturer-url=${HARDWARE_MANUFACTURER_URL}
          - nupano.description.model-name=${HARDWARE_MODEL_NAME}
          ${COMMENT_IF_UUID_IS_USED}- nupano.description.serial-number=${HARDWARE_SERIAL_NUMBER} #default: UUID of Runtime
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock   # access to docker socket
          - nupano_data:/nupano                         # persist nupano runtime data
        networks:
          - nupano_network
        ports:
          - 61100:61100/tcp
          - 61101:61101/tcp
          - 61106:61106/tcp

      nupano-discovery:
        restart: always
        image: ${NUPANO_RUNTIME_DISCOVERY_DOCKER_IMAGE_NAME}:${NUPANO_RUNTIME_VERSION}
        network_mode: host #-> SSDP
        environment:
          - logging.level.com.nupano=INFO #INFO, DEBUG or TRACE

      nupano-runtime-updater:
        user: root #required for windows to access docker.sock
        restart: always
        image: ${NUPANO_RUNTIME_UPDATER_DOCKER_IMAGE_NAME}:${NUPANO_RUNTIME_VERSION}
        environment:
          - logging.level.com.nupano=INFO #INFO, DEBUG or TRACE
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock   # access to docker socket
          - nupano_data:/nupano # persist nupano runtime data
        networks:
          - nupano_network
        ports:
          - 61107:61107/tcp

    networks:
      nupano_network:
        driver: bridge

    volumes:
      nupano_data:
    " > "$DOCKER_COMPOSE_FILE_PATH"

    local -r FILE_CONTENT=$(cat "$DOCKER_COMPOSE_FILE_PATH")
    log_message "File content:\n"
    log_message "$FILE_CONTENT"
    log_success "created docker-compose file"
}

install_nupano_runtime() {
    wget -O "$DOCKER_COMPOSE_FILE_PATH" | docker-compose up 
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
#TODO: check log file (headline,...)

check_root_priviliges
check_runtime_version_given "$1"
create_nupano_folder
create_log_file
#welcome_message
#ensure_dependencies
#install_docker
create_docker_compose_file                          #überarbeiten und einzeln testen: möglichkeit für default
#install_nupano_runtime

#log_success "NUPANO RUNTIME INSTALLATION FINISHED"