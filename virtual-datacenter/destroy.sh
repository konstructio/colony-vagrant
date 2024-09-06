#!/usr/bin/env bash

# Function to destroy the machines
destroy_nodes() {
  local nodes=("$@")

  for node in "${nodes[@]}"; do
    echo "Destroying machine: $node"
    vagrant destroy "$node" -f
    if [[ $? -ne 0 ]]; then
      echo "Error executing vagrant destroy $node"
      return 1
    fi
    echo "Destroyed machine $node"
  done

  # Sleep for 2 seconds after destruction
  echo "Sleeping for 2 seconds..."
  sleep 2
}

# Main logic
echo "Starting machine destruction process..."

# Store the original directory
user_original_dir=$(pwd)
if [[ $? -ne 0 ]]; then
  echo "Error getting current directory."
  exit 1
fi
echo "User current directory: $user_original_dir"

# Get the current directory based on the current file
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Change to the desired directory
cd "${DIR}/../" || {
  echo "Error changing to ${DIR}/../"
  exit 1
}

# Define the nodes to be destroyed
nodes=("control-plane-0" "control-plane-1" "control-plane-2" "compute-0" "compute-1" "compute-2")

# Run the destruction process
destroy_nodes "${nodes[@]}"
if [[ $? -ne 0 ]]; then
  echo "Error destroying nodes."
  exit 1
fi

# Change back to the original directory
cd "$user_original_dir" || {
  echo "Error changing back to original directory."
  exit 1
}

echo "Machine destruction process completed."
