#!/bin/bash

# Constants
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.csv"
USER_LIST_FILE="$1"  # The file containing user;groups data

# Functions
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | sudo tee -a "$LOG_FILE"
}

generate_password() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 12
}

# Ensure log file and password file exist
sudo touch "$LOG_FILE"
sudo mkdir -p /var/secure
sudo touch "$PASSWORD_FILE"
sudo chmod 600 "$PASSWORD_FILE"

# Check if user list file is provided
if [[ -z "$USER_LIST_FILE" ]]; then
    log "ERROR: No user list file provided."
    exit 1
fi

# Read the user list file
while IFS=";" read -r username groups; do
    username=$(echo "$username" | xargs) # Trim whitespace
    groups=$(echo "$groups" | xargs)     # Trim whitespace
    if [[ -z "$username" || -z "$groups" ]]; then
        log "ERROR: Malformed line - '$username;$groups'. Skipping."
        continue
    fi

    # Check if the user already exists
    if id "$username" &>/dev/null; then
        log "INFO: User $username already exists. Skipping."
        continue
    fi

    # Create personal group for the user
    if ! getent group "$username" &>/dev/null; then
        sudo groupadd "$username"
        log "INFO: Personal group $username created."
    else
        log "INFO: Personal group $username already exists."
    fi

    # Create additional groups
    IFS=',' read -ra group_list <<< "$groups"
    for group in "${group_list[@]}"; do
        group=$(echo "$group" | xargs) # Trim whitespace
        if [[ -n "$group" ]]; then
            if ! getent group "$group" &>/dev/null; then
                sudo groupadd "$group"
                log "INFO: Group $group created."
            else
                log "INFO: Group $group already exists."
            fi
        fi
    done

    # Create user with home directory and add to personal and additional groups
    group_string="$username,$groups"
    sudo useradd -m -g "$username" -G "$group_string" "$username"
    if [[ $? -eq 0 ]]; then
        log "INFO: User $username created and added to groups $group_string."
    else
        log "ERROR: Failed to create user $username."
        continue
    fi

    # Set up home directory permissions
    sudo chmod 700 "/home/$username"
    sudo chown "$username:$username" "/home/$username"
    log "INFO: Home directory for $username set up with correct permissions."

    # Generate and set password
    password=$(generate_password)
    echo "$username:$password" | sudo chpasswd
    if [[ $? -eq 0 ]]; then
        log "INFO: Password set for $username."
        echo "$username,$password" | sudo tee -a "$PASSWORD_FILE"
    else
        log "ERROR: Failed to set password for $username."
    fi

done < "$USER_LIST_FILE"

log "User and group creation script completed."
