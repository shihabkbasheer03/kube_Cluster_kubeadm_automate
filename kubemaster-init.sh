#!/bin/bash

# Set hostnames in /etc/hosts
echo "192.168.33.2 kubemaster" | sudo tee -a /etc/hosts
echo "192.168.33.3 kubenode1" | sudo tee -a /etc/hosts
echo "192.168.33.4 kubenode2" | sudo tee -a /etc/hosts

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Make it permanently loading
echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/k8s.conf

# Add the kernel parameters for IP forwarding
cat <<EOT | sudo tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT

# Apply sysctl settings
sudo sysctl --system

# Update package index and upgrade packages
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y apt-transport-https curl gnupg2 software-properties-common ca-certificates gpg

# Install Docker
sudo apt-get install -y docker.io

# Configure containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# Add Google’s apt key to verify releases for Kubernetes
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/k8s.gpg

# Add Kubernetes APT repository for Ubuntu 24.04 (noble)
echo 'deb [signed-by=/etc/apt/keyrings/k8s.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/k8s.list

# Update APT package index and install kubelet, kubeadm, and kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Prevent automatic updates/removals of Kubernetes packages
sudo apt-mark hold kubelet kubeadm kubectl

# Enable and start Kubelet service
sudo systemctl enable --now kubelet

echo "Provisioning completed successfully."

# Waiting for 12 seconds before initialization
sleep 12
echo "Waiting for 120 Seconds...."
echo "Let's initialize."

# Kubeadm initialization
IPADDR=192.168.33.2
POD_CIDR=10.244.0.0/16
NODENAME=kubemaster
kubeadm init --control-plane-endpoint=$IPADDR --pod-network-cidr=$POD_CIDR --node-name $NODENAME --ignore-preflight-errors Swap &>> /tmp/initout.log

# Wait for the kubeadm init process to complete
sleep 10

# Create the necessary directory for kubectl
cat /tmp/initout.log | grep -A2 mkdir | /bin/bash

# Give some time to finish the setup
sleep 10

# Output join command to be used by worker nodes
tail -2 /tmp/initout.log > /vagrant/cltjoincommand.sh