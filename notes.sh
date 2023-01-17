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