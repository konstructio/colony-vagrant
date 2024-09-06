#!/usr/bin/env bash

# shellcheck disable=SC1091
source ./scripts/colors.sh
source ./scripts/requirements.sh
source ./scripts/functions.sh
source ./scripts/text.sh
source ./scripts/civo.sh

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
            setup_vagrant
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
