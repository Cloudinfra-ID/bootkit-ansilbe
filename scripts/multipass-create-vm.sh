#!/bin/bash

# Multipass VM Creation Script
# This script creates multiple VMs using multipass with user-defined specifications

echo "=== Multipass VM Creation Script ==="
echo

# Function to validate numeric input
validate_number() {
    local input=$1
    local name=$2
    
    if ! [[ "$input" =~ ^[0-9]+$ ]] || [ "$input" -le 0 ]; then
        echo "Error: $name must be a positive integer."
        return 1
    fi
    return 0
}

# Function to validate memory size format
validate_memory() {
    local input=$1
    
    if ! [[ "$input" =~ ^[0-9]+[GMgm]?$ ]]; then
        echo "Error: Memory size must be in format like '2G', '1024M', or '2048' (MB assumed if no unit)"
        return 1
    fi
    return 0
}

# Function to validate disk size format
validate_disk() {
    local input=$1
    
    if ! [[ "$input" =~ ^[0-9]+[GMgm]?$ ]]; then
        echo "Error: Disk size must be in format like '10G', '2048M', or '10240' (MB assumed if no unit)"
        return 1
    fi
    return 0
}

# Function to validate VM name
validate_vm_name() {
    local input=$1
    
    if ! [[ "$input" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Error: VM name can only contain letters, numbers, hyphens, and underscores."
        return 1
    fi
    return 0
}

# Function to check if SSH key exists
check_ssh_key() {
    local ssh_key_path="$HOME/.ssh/id_rsa.pub"
    
    if [ ! -f "$ssh_key_path" ]; then
        echo "Warning: SSH public key not found at $ssh_key_path"
        return 1
    fi
    
    if [ ! -r "$ssh_key_path" ]; then
        echo "Warning: SSH public key at $ssh_key_path is not readable"
        return 1
    fi
    
    return 0
}

# Function to add SSH key to VM
add_ssh_key_to_vm() {
    local vm_name=$1
    local ssh_key_path="$HOME/.ssh/id_rsa.pub"
    
    echo "  Adding SSH key to VM: $vm_name"
    
    # Wait for VM to be ready
    echo "  Waiting for VM to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if sudo multipass exec "$vm_name" -- echo "VM is ready" >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo "  ✗ Timeout waiting for VM to be ready"
        return 1
    fi
    
    # Read the SSH public key
    local ssh_key_content
    ssh_key_content=$(cat "$ssh_key_path")
    
    # Add SSH key to authorized_keys
    if sudo multipass exec "$vm_name" -- bash -c "
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        echo '$ssh_key_content' >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        sort ~/.ssh/authorized_keys | uniq > ~/.ssh/authorized_keys.tmp
        mv ~/.ssh/authorized_keys.tmp ~/.ssh/authorized_keys
    "; then
        echo "  ✓ SSH key added successfully"
        return 0
    else
        echo "  ✗ Failed to add SSH key"
        return 1
    fi
}

# Get CPU count
while true; do
    read -p "Enter CPU count (e.g., 2): " cpu_count
    if validate_number "$cpu_count" "CPU count"; then
        break
    fi
done

# Get memory size
while true; do
    read -p "Enter memory size (e.g., 2G, 1024M): " memory_size
    if validate_memory "$memory_size"; then
        break
    fi
done

# Get disk size
while true; do
    read -p "Enter disk size (e.g., 10G, 2048M): " disk_size
    if validate_disk "$disk_size"; then
        break
    fi
done

# Get VM base name
while true; do
    read -p "Enter VM base name (e.g., myvm): " vm_name
    if validate_vm_name "$vm_name"; then
        break
    fi
done

# Get VM count
while true; do
    read -p "Enter number of VMs to create: " vm_count
    if validate_number "$vm_count" "VM count"; then
        break
    fi
done

# Check SSH key availability
ssh_key_available=false
ssh_key_path="$HOME/.ssh/id_rsa.pub"

if check_ssh_key; then
    ssh_key_available=true
    echo "✓ SSH public key found at $ssh_key_path"
else
    echo "SSH key setup will be skipped for VMs"
fi

# Ask about SSH key configuration
configure_ssh=false
if [ "$ssh_key_available" = true ]; then
    read -p "Do you want to configure SSH key access for VMs? (Y/n): " ssh_confirm
    if [[ ! "$ssh_confirm" =~ ^[Nn]$ ]]; then
        configure_ssh=true
    fi
fi

echo
echo "=== Configuration Summary ==="
echo "CPU Count: $cpu_count"
echo "Memory Size: $memory_size"
echo "Disk Size: $disk_size"
echo "VM Base Name: $vm_name"
echo "Number of VMs: $vm_count"
echo "SSH Key Configuration: $([ "$configure_ssh" = true ] && echo "Enabled" || echo "Disabled")"
echo

# Confirm before proceeding
read -p "Do you want to proceed with VM creation? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo
echo "=== Creating VMs ==="

# Create VMs
for ((i=1; i<=vm_count; i++)); do
    # Format VM name with zero-padded suffix
    vm_full_name="${vm_name}-$(printf "%02d" $i)"
    
    echo "Creating VM: $vm_full_name"
    
    # Execute multipass launch command
    echo sudo multipass launch -m "$memory_size" -c "$cpu_count" -d "$disk_size" -n "$vm_full_name"
    if sudo multipass launch -m "$memory_size" -c "$cpu_count" -d "$disk_size" -n "$vm_full_name"; then
        echo "✓ Successfully created VM: $vm_full_name"
        
        # Configure SSH key if enabled
        if [ "$configure_ssh" = true ]; then
            if add_ssh_key_to_vm "$vm_full_name"; then
                echo "✓ SSH key configured for VM: $vm_full_name"
            else
                echo "✗ Failed to configure SSH key for VM: $vm_full_name"
            fi
        fi
    else
        echo "✗ Failed to create VM: $vm_full_name"
        echo "Error occurred. You may want to check multipass status and logs."
        
        # Ask if user wants to continue with remaining VMs
        if [ $i -lt $vm_count ]; then
            read -p "Continue creating remaining VMs? (y/N): " continue_confirm
            if [[ ! "$continue_confirm" =~ ^[Yy]$ ]]; then
                echo "Stopping VM creation process."
                exit 1
            fi
        fi
    fi
    
    echo
done

echo "=== VM Creation Complete ==="
echo "Created VMs with names: ${vm_name}-01 to ${vm_name}-$(printf "%02d" $vm_count)"

if [ "$configure_ssh" = true ]; then
    echo
    echo "=== SSH Access ==="
    echo "SSH keys have been configured for all VMs."
    echo "To connect via SSH, first get the VM IP address:"
    echo "  multipass list"
    echo "Then connect using:"
    echo "  ssh ubuntu@<vm-ip-address>"
    echo
    echo "Alternatively, you can still use multipass shell:"
    echo "  multipass shell <vm-name>"
fi

echo
echo "=== Useful Commands ==="
echo "To list all VMs: multipass list"
echo "To connect to a VM: multipass shell <vm-name>"
echo "To get VM info: multipass info <vm-name>"
echo "To stop all VMs: multipass stop --all"
echo "To delete a VM: multipass delete <vm-name> && multipass purge"