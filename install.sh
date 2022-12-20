#!/bin/bash
set -eu

#call: $ sudo su -c "bash <(wget -qO- https://raw.githubusercontent.com/mosaiqone/Linux-runtime-install-script/main/install.sh latest)" root

################################################################################
# Parameters
################################################################################
readonly NUPANO_RUNTIME_IMAGE_URL=public.ecr.aws/d9n0g1v8/nupano-runtime
readonly NUPANO_RUNTIME_DISCOVERY_IMAGE_URL=public.ecr.aws/d9n0g1v8/nupano-runtime-discovery
readonly NUPANO_RUNTIME_UPDATER_IMAGE_URL=public.ecr.aws/d9n0g1v8/nupano-runtime-updater

# Color Definitions
readonly RED='\e[1;31m'
readonly GREEN='\e[1;32m'
readonly CYAN='\e[1;36m'
readonly ORANGE='\e[1;33m'
readonly NC='\e[0m'

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
# Function Definition
################################################################################
check_root_priviliges() {
    local -r RED='\e[1;31m'
    local -r NC='\e[0m'

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


set_docker_proxy() {


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





create_docker_compose_file() {
    log_headline "Create Typeplate File"

    NUPANO_RUNTIME_VERSION


   log_message "Please provide information about the hardware which hosts the NUPANO Runtime:\n"
    local -r NAME_REGEX='^[A-Za-z0-9\ _\.-]+$'
    while true; do
        get_checked_user_input "Please enter the hardware manufacturer name: " \
            "$NAME_REGEX" \
            "typeplateManufacturer"

        get_checked_user_input "Please enter the hardware manufacturer URL: " \
            '[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]' \
            "typeplateManufacturerUrl"

        get_checked_user_input "Please enter the hardware model name: " \
            "$NAME_REGEX" \
            "typeplateModelName"

        get_checked_user_input "Please enter the hardware serial number: " \
            "$NAME_REGEX" \
            "typeplateSerialNumber"

        log_message "\nThe typeplate.xml file details are:\n" 
        log_message_safe "Manufacturer name: '${typeplateManufacturer}'"
        log_message_safe "Manufacturer URL: '${typeplateManufacturerUrl}'"
        log_message_safe "Model name: '${typeplateModelName}'"
        log_message_safe "Serial number: '${typeplateSerialNumber}'"
        
        if evaluate_yes_no_answer "Are you sure that the entered input is correct? (Yes/no)" "y"; then
            break
        fi
    done




    local -r TYPEPLATE_DIRECTORY=/etc/nupano
    local -r TYPEPLATE_FILE_PATH="${TYPEPLATE_DIRECTORY}/typeplate.xml"

    log_message "Create typeplate directory '${TYPEPLATE_DIRECTORY}'…"
    mkdir -p /etc/nupano  
    log_success "created typeplate directory"

    log_message "Create random UUID for the runtime…"
    local -r RANDOM_UUID=$(cat /proc/sys/kernel/random/uuid)
    log_message "New UUID: '${RANDOM_UUID}'"
    log_success "new UUID created"

    log_message "Create typeplate file…"
    echo "<?xml version=\"1.0\"?>
    <root xmlns=\"urn:schemas-upnp-org:device-1-0\" configId=\"configuration number\">
        <specVersion>
            <major>2</major>
            <minor>0</minor>
        </specVersion>
        <device>
            <deviceType>urn:nupano-com:device:nupano-runtime:1</deviceType>
            <friendlyName>NUPANO Runtime</friendlyName>
            <manufacturer>${TYPEPLATE_MANUFACTURER:-}</manufacturer>
            <manufacturerURL>${TYPEPLATE_MANUFACTURER_URL:-}</manufacturerURL>
            <modelName>${TYPEPLATE_MODEL_NAME:-}</modelName>
            <serialNumber>${TYPEPLATE_SERIAL_NUMBER:-}</serialNumber>
            <UDN>uuid:$RANDOM_UUID</UDN>
        </device>
    </root>
    " > "$TYPEPLATE_FILE_PATH"

    version: '3.3'

    services:

      nupano-runtime:
        user: root #required for windows to access docker.sock
        restart: always
        image: public.ecr.aws/d9n0g1v8/nupano-runtime:latest
        environment:
          - logging.level.com.nupano=INFO #INFO, DEBUG or TRACE
          - nupano.description.manufacturer=Lenze SE
          - nupano.description.manufacturer-url=www.lenze.com
          - nupano.description.model-name=Virtual Runtime
          #- nupano.description.serial-number #default: UUID of Runtime
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
        image: public.ecr.aws/d9n0g1v8/nupano-runtime-discovery:latest
        network_mode: host #-> SSDP
        environment:
          - logging.level.com.nupano=INFO #INFO, dEBUG or TRACE

      nupano-runtime-updater:
        user: root #required for windows to access docker.sock
        restart: always
        image: public.ecr.aws/d9n0g1v8/nupano-runtime-updater:latest
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



    local -r FILE_CONTENT=$(cat "$TYPEPLATE_FILE_PATH")
    log_message "File content:"
    log_message "$FILE_CONTENT"
    log_success "created typeplate file"
    log_message "Restrict typeplate file permissions to readonly…"
    chmod 444 "$TYPEPLATE_FILE_PATH"
    log_success "set new file permissions"
}

install_nupano_runtime() {
    local -r DOCKER_COMPOSE_FILE_PATH=${NUPANO_FOLDER}/docker-compose.yml
    wget -O "$DOCKER_COMPOSE_FILE_PATH" | docker-compose up 
}


################################################################################
# Installation Script Sequence
################################################################################
#TODO: check log file (headline,...)

check_root_priviliges
check_runtime_version_given
create_nupano_folder
create_log_file
welcome_message
set_docker_proxy                                    #TODO: set proxy for docker
ensure_dependencies
install_docker
create_docker_compose_file                          #überarbeiten und einzeln testen: möglichkeit für default
install_nupano_runtime

log_success "NUPANO RUNTIME INSTALLATION FINISHED"