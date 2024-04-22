
# instance_data=("$@")
# for data in "${instance_data[@]}"; do
#     read -r ip user link <<< "$data"    
#     echo "Processing instance at IP: $ip, user: $user, cloning repository: $link"
#     ssh "$user@$ip" "git clone $link"
# done

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

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
