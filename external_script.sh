# instance_data=("$@")
# for data in "${instance_data[@]}"; do
#     read -r ip user link <<< "$data"    
#     echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"
#     ssh "$user@$ip" "git clone $link"
# done


# # -----------------------
# !/bin/bash

# # Assign instance data as a string
# instance_data='[["10.138.0.39","centos","https://github.com/ankitr-c/DT-Terraform.git"],["10.138.0.38","centos","https://github.com/ankitr-c/DT-Terraform.git"],["10.138.0.38","centos","https://github.com/ankitr-c/DT-Terraform.git"]]'

# # Remove outer brackets and split the string by comma and space
# IFS=',' read -r -a instance_data_arr <<< "${instance_data:2:-2}"

# # Loop through each instance data
# for ((i = 0; i < ${#instance_data_arr[@]}; i += 3)); do
#     # Read IP, user, and link
#     ip="${instance_data_arr[i]}"
#     user="${instance_data_arr[i + 1]}"
#     link="${instance_data_arr[i + 2]}"

#     # Print instance information
#     echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"

#     # SSH and clone repository
#     ssh "$user@$ip" "git clone $link"
# done
# # ----------------

# #!/bin/bash

# # Get instance data from the command line argument
# instance_data="$1"

# # Remove outer brackets and split the string by comma and space
# IFS=', ' read -r -a instance_data_arr <<< "${instance_data:2:-2}"

# # Loop through each instance data
# for ((i = 0; i < ${#instance_data_arr[@]}; i += 3)); do
#     # Read IP, user, and link
#     ip="${instance_data_arr[i]}"
#     user="${instance_data_arr[i + 1]}"
#     link="${instance_data_arr[i + 2]}"

#     # Print instance information
#     echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"

#     # SSH and clone repository
#     ssh "$user@$ip" "git clone $link"
# done
# -------
# #!/bin/bash

# # Get instance data from the command line argument
# instance_data="$1"

# # Extract IP, user, and link using jq
# ip=$(echo "$instance_data" | jq -r '.[][0]')
# user=$(echo "$instance_data" | jq -r '.[][1]')
# link=$(echo "$instance_data" | jq -r '.[][2]')

# # Loop through each instance data
# for i in "${!ip[@]}"; do
#     # Print instance information
#     echo "Processing instance at IP: ${ip[i]}, user: ${user[i]}, cloning repository: ${link[i]}"

#     # SSH and clone repository
#     ssh "${user[i]}@${ip[i]}" "git clone ${link[i]}"
# done

# # !/bin/bash

# # Assign instance data as a string
# instance_data='[["10.138.0.39","centos","https://github.com/ankitr-c/DT-Terraform.git"],["10.138.0.38","centos","https://github.com/ankitr-c/DT-Terraform.git"],["10.138.0.38","centos","https://github.com/ankitr-c/DT-Terraform.git"]]'

# # Remove outer brackets and split the string by comma and space
# IFS=',' read -r -a instance_data_arr <<< "${instance_data:2:-2}"

# # Loop through each instance data
# for ((i = 0; i < ${#instance_data_arr[@]}; i += 3)); do
#     # Read IP, user, and link
#     ip="${instance_data_arr[i]}"
#     user="${instance_data_arr[i + 1]}"
#     link="${instance_data_arr[i + 2]}"

#     ip="${ip#"?[{"}"
#     ip="${ip%"?]}"}"
#     link="${link#"?[{"}"
#     link="${link%"?]}"}"

#     # Print instance information
#     echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"

#     # SSH and clone repository
#     ssh "$user@$ip" "git clone $link"
# done

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# #!/bin/bash

# # Assign instance data as a string
# # instance_data='[["10.138.0.39","centos","https://github.com/ankitr-c/DT-Terraform.git"],["10.138.0.38","centos","https://github.com/ankitr-c/DT-Terraform.git"],["10.138.0.38","centos","https://github.com/ankitr-c/DT-Terraform.git"]]'

# #!/bin/bash

# # Check if the argument is provided
# if [ $# -ne 1 ]; then
#     echo "Usage: $0 \"IPaddress,user,link\""
#     exit 1
# fi

# # Split the input string into an array
# IFS=',' read -r -a input_array <<< "$1"

# # Extract IP, user, and link from the array
# name="${input_array[0]}"
# user="${input_array[1]}"
# link="${input_array[2]}"
# zone="${input_array[3]}"


# # Print instance information
# echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"

# # SSH and clone repository
# # ssh "$user@$ip" "git clone $link"
# gcloud compute ssh $user@$name --zone=$zone --tunnel-through-iap --command "sudo yum install -y git && git clone $link"

# # XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


#!/bin/bash

# Extract the variables from the environment
name=$NAME
user=$USER
link=$LINK
zone=$ZONE

# Print instance information
echo "Processing instance at IP: $name, user: $user, cloning repository: $link"

# SSH and clone repository
gcloud compute ssh "$user@$name" --zone="$zone" --tunnel-through-iap --command "sudo yum install -y git && git clone $link"