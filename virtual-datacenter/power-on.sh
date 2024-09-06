#!/usr/bin/env bash

# Function to power on hardware and sleep between each power-on
run_and_sleep() {
  local nodes=("$@")
  local sleep_time=30

  for i in "${!nodes[@]}"; do
    node="${nodes[$i]}"

    echo "Powering on machine: $node"
    vagrant up "$node"
    if [[ $? -ne 0 ]]; then
      echo "Error executing vagrant up $node"
      return 1
    fi

    echo "Powered on machine $node"

    # Sleep if not the last machine
    if [[ $i -ne $((${#nodes[@]} - 1)) ]]; then
      echo "Sleeping for $sleep_time seconds..."
      sleep "$sleep_time"
    fi
  done
}

# Main logic
echo "Starting power-on process..."

# Store the original directory
user_original_dir=$(pwd)
if [[ $? -ne 0 ]]; then
  echo "Error getting current directory."
  exit 1
fi
echo "User current directory: $user_original_dir"

# Change to the desired directory
cd /root/colony/vagrant-dc || {
  echo "Error changing to /root/colony/vagrant-dc."
  exit 1
}

# Define the nodes to be powered on
nodes=("control-plane-0" "control-plane-1" "control-plane-2" "compute-0" "compute-1" "compute-2")

# Run the power-on process
run_and_sleep "${nodes[@]}"
if [[ $? -ne 0 ]]; then
  echo "Error powering on nodes."
  exit 1
fi

# Change back to the original directory
cd "$user_original_dir" || {
  echo "Error changing back to original directory."
  exit 1
}

echo "Power-on process completed."
