# ip=$(gcloud filestore instances describe ${name} --project=${project} --zone=${zone} | grep -A1 'ipAddresses' | awk 'NR==2 {print $2}')
# mount -t nfs -o timeo=300 ${ip}:/testing /home/centos/NFS_Mount

# touch /home/centos/NFS_Mount/test
# echo $ip > /home/centos/test_ip




# mount -t nfs -o timeo=300 ${nfs_ip}:/testing /home/centos/NFS_Mount


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

# XXXXXXXXXXXXXXX--Below Is Stable Script--XXXXXXXXXXXXXXXXXX
# #!/bin/bash

# # Extract the variables from the environment
# name=$NAME
# user=$USER
# link=$LINK
# zone=$ZONE

# # Print instance information
# echo "Processing instance at IP: $name, user: $user, cloning repository: $link"

# # SSH and clone repository
# gcloud compute ssh "$user@$name" --zone="$zone" --tunnel-through-iap --command "sudo yum install -y git && git clone $link"

# XXXXXXXXXXXXXXX--Above Is Stable Script--XXXXXXXXXXXXXXXXXX




# ---------------------------------------------



# yum install -y git
# git clone ${INSTANCE_CONFIG_LINK} /home/centos/project
# yum install wget screen -y

# ---------------------------------------------

# #!bin/bash
# yum install screen -y
# # Run the while loop in the background for 60 seconds
# seconds=0
# while [ $seconds -lt 60 ]; do
#     echo "Main Screen - Second: $seconds"
#     sleep 1
#     ((seconds++))
# done &

# # Start a screen session in the foreground and run the while loop for 120 seconds
# screen -S myscreen bash -c '
# seconds=0
# while [ $seconds -lt 58 ]; do
#     echo "Screen 1 - Second: $seconds"
#     sleep 1
#     ((seconds++))
# done
# exit
# '
# wait 

# exit

# ---------------------------------------------
# mkdir /home/ankitraut0987/logs
# cd /home/ankitraut0987/logs/
# touch script.log
# min=0
# while [ $seconds -lt 5 ]; do
#     echo "Main Screen - Min: $min"
#     sleep 60
#     "--------------------------" >> script.log
#     uptime >> script.log
#     ((min++))
# done


# #!/bin/bash
# mkdir -p /home/ankitraut0987/logs
# cd /home/ankitraut0987/logs/
# > script.log

# min=0

# while [ $min -lt 5 ]; do
#     echo "Main Screen - Min: $min"
#     echo "--------------------------" >> script.log
#     uptime >> script.log
#     sleep 60
#     ((min++))
# done

