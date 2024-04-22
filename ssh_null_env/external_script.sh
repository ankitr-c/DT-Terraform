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