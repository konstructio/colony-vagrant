#!/usr/bin/env bash

# Get directory relative to this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

source "${DIR}/scripts/colors.sh"
source "${DIR}/scripts/requirements.sh"
source "${DIR}/scripts/functions.sh"
source "${DIR}/scripts/text.sh"
source "${DIR}/scripts/civo.sh"

install_gum
install_jq
install_civo_cli

colony_title

recover_vars
if [ $? -ne 0 ]; then
    collect_user_data
    save_collected_data
    clear
else
    if ! ask_skip_data_collection; then
        collect_user_data
        save_collected_data
        clear
    fi
fi

main() {
    civo_setup
    while true; do
        echo -e "\n${GREEN}Select some action:${NOCOLOR}\n"
        ACTION=$(gum choose "create datacenter" "destroy datacenter" "ssh datacenter-vm" "ssh laptop" "show config" "get ssh config" "exit")

        case $ACTION in
        "create datacenter")
            create_ssh_key
            unblock_local_ssh
            create_datacenter
            wait_for_civo_status
#            setup_vagrant
            ;;
        "destroy datacenter")
            civo_destroy
            ;;
        "ssh datacenter-vm")
            civo_ssh_command
            ;;
        "ssh laptop")
            access_ssh_laptop
            ;;
        "show config")
            show_config
            ;;
        "get ssh config")
            get_ssh_config
            ;;
        "exit")
            echo "bye..."
            break
            ;;
        *)
            echo "Option not found: $ACTION, bye..."
            exit 1
            ;;
        esac
    done
}

main
