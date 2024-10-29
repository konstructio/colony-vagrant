#!/usr/bin/env bash


# Check if the script received exactly one argument
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 filename"
  exit 1
fi

filename="$1"

# Check if the file exists
if [ ! -f "$filename" ]; then
  echo "Error: File '$filename' does not exist."
  exit 1
fi

# Fix: temporarily removed for incompatible helm version
# helm upgrade tink-stack -n tink-system -f "$filename" oci://ghcr.io/tinkerbell/charts/stack

kubectl -n tink-system patch clusterrole smee-role --type='json' -p='[
  {"op": "add", "path": "/rules/0/verbs/-", "value": "create"},
  {"op": "add", "path": "/rules/0/verbs/-", "value": "update"}
]'
