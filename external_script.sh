# instance_data=("$@")
# for data in "${instance_data[@]}"; do
#     read -r ip user link <<< "$data"    
#     echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"
#     ssh "$user@$ip" "git clone $link"
# done



#!/bin/bash

# Parse JSON encoded input as associative arrays
declare -A instance_array
IFS=$'\n+' eval 'instance_array=( '"$(printf '%s' "${instance_data}"| jq -r '.[] | @base64 )"'"' )'
unset IFS

for instance in "${!instance_array[@]}"; do
  decoded_instance=$(echo "${instance_array[$instance]}" | base64 --decode)
  # Convert the JSON into bash variables
  eval "$decoded_instance"
  echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"
  ssh "$user@$ip" "git clone $link"
done