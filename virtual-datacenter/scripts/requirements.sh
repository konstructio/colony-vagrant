install_gum() {
  if command -v gum &> /dev/null
  then
    return
  fi

  echo "installing gum"
  echo OSTYPE: $OSTYPE
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Linux"
    echo 'deb [trusted=yes] https://repo.charm.sh/apt/ /' | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install gum
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "MAC OSX"
    brew install gum >/dev/null 2>&1;
  elif [[ "$OSTYPE" == "cygwin" ]]; then
    echo "POSIX compatibility layer and Linux environment emulation for Windows"
  elif [[ "$OSTYPE" == "msys" ]]; then
    echo "Lightweight shell and GNU utilities compiled for Windows (part of MinGW)"
  elif [[ "$OSTYPE" == "win32" ]]; then
    echo "I'm not sure this can happen."
  elif [[ "$OSTYPE" == "freebsd"* ]]; then
    echo "Freebsd"
  else
    echo -e "${RED}Hmmmm, I don't know your OS...${NOCOLOR}"
    echo "Linux"
    echo 'deb [trusted=yes] https://repo.charm.sh/apt/ /' |  tee /etc/apt/sources.list.d/charm.list
    apt update && apt install gum
  fi
  echo -e "${NOCOLOR}"
}

install_civo_cli() {
  if command -v civo &> /dev/null
  then
    return
  fi

  echo "installing civo cli"
  #  sudo curl -sL https://civo.com/get | sh
  brew tap civo/tools
  brew install civo
}

install_jq() {
  if command -v jq &> /dev/null
  then
    return
  fi

  brew install jq
}

civo_setup() {
  echo -e "${GREEN}Setting up Civo CLI${NOCOLOR}"
  civo apikey save kubefirst-team $TF_VAR_civo_token
  civo region use $TF_VAR_civo_region
}

recover_vars() {
    if [ ! -f data.txt ]; then
        echo -e "${YELLOW}You have not any data file yet.${NOCOLOR}"
        return 1
    fi
    while IFS=':' read -r key value; do
        if [ -z "$value" ]; then
           echo "The variable $key is empty or null. Please make sure all variables are defined."
           return 1
        fi
#        echo "export $key=$value"
        export "$key"="$value"
    done < data.txt

    # Check if all expected variables are defined
    if [ -z "$KUBEFIRST_TEAM_INFO" ]; then echo "KUBEFIRST_TEAM_INFO is not defined"; return 1; fi
    if [ -z "$CIVO_REGION" ]; then echo "CIVO_REGION is not defined"; return 1; fi
    if [ -z "$TF_VAR_civo_token" ]; then echo "TF_VAR_civo_token is not defined"; return 1; fi
    if [ -z "$SELECTED_KEY" ]; then echo "SELECTED_KEY is not defined"; return 1; fi
    if [ -z "$TF_VAR_ssh_key_pub" ]; then echo "TF_VAR_ssh_key_pub is not defined"; return 1; fi
    if [ -z "$TF_VAR_civo_region" ]; then echo "TF_VAR_civo_region is not defined"; return 1; fi
    if [ -z "$GITHUB_USER" ]; then echo "GITHUB_USER is not defined"; return 1; fi
    if [ -z "$GITHUB_TOKEN" ]; then echo "GITHUB_TOKEN is not defined"; return 1; fi
    if [ -z "$COLONY_API_KEY" ]; then echo "COLONY_API_KEY is not defined"; return 1; fi
    if [ -z "$COLONY_BRANCH" ]; then echo "COLONY_BRANCH is not defined"; return 1; fi
}

choose_option() {
    local selected="$1"
    shift
    if [ -n "$selected" ]; then
        gum choose --selected "$selected" "$@"
    else
        gum choose "$@"
    fi
}

capture_input() {
    local placeholder="$1"
    local default_value="$2"
    local is_password="$3"
    if [ -n "$default_value" ]; then
        if [ "$is_password" = true ]; then
            gum input --placeholder "$placeholder" --password --value "$default_value"
        else
            gum input --placeholder "$placeholder" --value "$default_value"
        fi
    else
        if [ "$is_password" = true ]; then
            gum input --placeholder "$placeholder" --password
        else
            gum input --placeholder "$placeholder"
        fi
    fi
}


show_config() {
  echo -e "${REED}Do you want to show sensitive values? (no/yes)${NOCOLOR}"
  local response=$(choose_option "no" "yes" "no")
   if [[ "$response" == "yes" ]]; then
      echo -e "${GREEN}KUBEFIRST_TEAM_INFO:${NOCOLOR} $KUBEFIRST_TEAM_INFO"
      echo -e "${GREEN}CIVO_REGION:${NOCOLOR} $CIVO_REGION"
      echo -e "${GREEN}TF_VAR_civo_token ${NOCOLOR} $TF_VAR_civo_token"
      echo -e "${GREEN}TF_VAR_ssh_key_pub ${NOCOLOR} $TF_VAR_ssh_key_pub"
      echo -e "${GREEN}SELECTED_KEY ${NOCOLOR} $SELECTED_KEY"
      echo -e "${GREEN}TF_VAR_civo_region ${NOCOLOR} $CIVO_REGION"
      echo -e "${GREEN}INSTANCE_NAME ${NOCOLOR} colony-$KUBEFIRST_TEAM_INFO"
      echo -e "${GREEN}GITHUB_USER ${NOCOLOR} $GITHUB_USER"
      echo -e "${GREEN}GITHUB_TOKEN ${NOCOLOR} $GITHUB_TOKEN"
      echo -e "${GREEN}COLONY_API_KEY ${NOCOLOR} $COLONY_API_KEY"
      echo -e "${GREEN}COLONY_BRANCH ${NOCOLOR} $COLONY_BRANCH"
      return 0
    elif [[ "$response" == "no" ]]; then
      echo -e "${GREEN}KUBEFIRST_TEAM_INFO:${NOCOLOR} $KUBEFIRST_TEAM_INFO"
      echo -e "${GREEN}CIVO_REGION:${NOCOLOR} $CIVO_REGION"
      echo -e "${GREEN}TF_VAR_civo_token ${NOCOLOR} ************"
      echo -e "${GREEN}TF_VAR_ssh_key_pub ${NOCOLOR} $TF_VAR_ssh_key_pub"
      echo -e "${GREEN}TF_VAR_civo_region ${NOCOLOR} $CIVO_REGION"
      echo -e "${GREEN}INSTANCE_NAME ${NOCOLOR} colony-$KUBEFIRST_TEAM_INFO"
      echo -e "${GREEN}GITHUB_USER ${NOCOLOR} $GITHUB_USER"
      echo -e "${GREEN}GITHUB_TOKEN ${NOCOLOR} ************"
      echo -e "${GREEN}COLONY_API_KEY ${NOCOLOR}  ************"
      echo -e "${GREEN}COLONY_BRANCH ${NOCOLOR} $COLONY_BRANCH"
      return 0
    else
      show_vars
    fi
}

collect_user_data() {
  echo -e "${GREEN}Select the region where you want to deploy the VM${NOCOLOR} (default:$GREEN $CIVO_REGION $NOCOLOR)"
  CIVO_REGION=$(choose_option "$CIVO_REGION" "nyc1" "lon1" "fra1" "sfo1" "mia1" "syd1")
  export CIVO_REGION

  echo -e "${GREEN}Please enter your CIVO token${NOCOLOR}"
  CIVO_TOKEN=$(capture_input "put your CIVO token" "$TF_VAR_civo_token" true)
  export TF_VAR_civo_token=$CIVO_TOKEN

  echo -e "${GREEN}Select the SSH key to use${NOCOLOR}"
  KEYS=($(ls ~/.ssh/*.pub))
  SELECTED_KEY=$(choose_option "$SSH_KEY_PUB" "${KEYS[@]}")
  export TF_VAR_ssh_key_pub=$(cat $SELECTED_KEY)
  export SELECTED_KEY=$SELECTED_KEY

  echo -e "${GREEN}Please enter your GitHub user${NOCOLOR} (default:$GREEN $GITHUB_USER $NOCOLOR)"
  export GITHUB_USER=$(capture_input "put your GitHub user" "$GITHUB_USER" false)

  echo -e "${GREEN}Please enter your GitHub token${NOCOLOR} (default:$GREEN ********** $NOCOLOR)"
  export GITHUB_TOKEN=$(capture_input "put your GitHub token" "$GITHUB_TOKEN" true)

  echo -e "${GREEN}Please enter your KUBEFIRST_TEAM_INFO${NOCOLOR} (default:$GREEN $KUBEFIRST_TEAM_INFO $NOCOLOR)"
  export KUBEFIRST_TEAM_INFO=$(capture_input "put your KUBEFIRST_TEAM_INFO" "$KUBEFIRST_TEAM_INFO" false)

  echo -e "${GREEN}Please enter your COLONY_API_KEY${NOCOLOR} (default:$GREEN ********** $NOCOLOR)"
  export COLONY_API_KEY=$(capture_input "put your COLONY_API_KEY" "$COLONY_API_KEY" true)

  echo -e "${GREEN}Please enter your COLONY_BRANCH${NOCOLOR} (default:$GREEN $COLONY_BRANCH $NOCOLOR)"
  export COLONY_BRANCH=$(capture_input "put your COLONY_BRANCH" "$COLONY_BRANCH" false)
}

save_collected_data() {
  {
    echo "KUBEFIRST_TEAM_INFO:$KUBEFIRST_TEAM_INFO"
    echo "CIVO_REGION:$CIVO_REGION"
    echo "TF_VAR_civo_token:$CIVO_TOKEN"
    echo "TF_VAR_ssh_key_pub:$TF_VAR_ssh_key_pub"
    echo "SELECTED_KEY:$SELECTED_KEY"
    echo "TF_VAR_civo_region:$CIVO_REGION"
    echo "GITHUB_USER:$GITHUB_USER"
    echo "GITHUB_TOKEN:$GITHUB_TOKEN"
    echo "COLONY_API_KEY:$COLONY_API_KEY"
    echo "COLONY_BRANCH:$COLONY_BRANCH"
  } > data.txt
}
