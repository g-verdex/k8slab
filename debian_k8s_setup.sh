#!/bin/bash
#
# Kubernetes Node Preparation Script for Debian
# This script prepares a Debian system for Kubernetes installation
# by configuring all necessary prerequisites.
#

set -e  # Exit on any error

echo "==========================================================="
echo "Preparing system for Kubernetes installation..."
echo "==========================================================="

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo or switch to the root user."
    exit 1
fi

# 1. Update system
echo "[1/9] Updating system packages..."
apt update && apt upgrade -y

# 2. Install dependencies
echo "[2/9] Installing dependencies..."
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# 3. Load necessary kernel modules
echo "[3/9] Configuring kernel modules..."
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# 4. Set required sysctl parameters
echo "[4/9] Setting system parameters..."
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# 5. Disable swap (Kubernetes requirement)
echo "[5/9] Disabling swap..."
swapoff -a
sed -i '/swap/d' /etc/fstab

# 6. Install container runtime (containerd)
echo "[6/9] Installing containerd..."
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt update
apt install -y containerd.io

# 7. Configure containerd
echo "[7/9] Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# 8. Install Kubernetes packages
echo "[8/9] Installing Kubernetes components..."
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# 9. Configure /etc/hosts for cluster communication
echo "[9/9] Setting up hosts file (update with your actual IPs)..."
cat <<EOF | tee -a /etc/hosts
# Update these IPs to match your actual setup
192.168.1.10 frontend-master
192.168.1.11 frontend-worker
192.168.1.40 db-master
192.168.1.41 db-worker
EOF

# Prompt for hostname configuration
echo -e "\nWould you like to set the hostname for this node? [y/N] "
read -r SET_HOSTNAME

if [[ "$SET_HOSTNAME" =~ ^[Yy]$ ]]; then
    echo "Please select the node type:"
    echo "1) Frontend Master"
    echo "2) Frontend Worker"
    echo "3) Database Master"
    echo "4) Database Worker"
    echo "5) Custom"
    read -r NODE_TYPE
    
    case $NODE_TYPE in
        1) hostnamectl set-hostname frontend-master ;;
        2) hostnamectl set-hostname frontend-worker ;;
        3) hostnamectl set-hostname db-master ;;
        4) hostnamectl set-hostname db-worker ;;
        5) 
            echo "Enter custom hostname: "
            read -r CUSTOM_HOSTNAME
            hostnamectl set-hostname "$CUSTOM_HOSTNAME"
            ;;
        *) echo "Skipping hostname configuration." ;;
    esac
fi

echo "==========================================================="
echo "Kubernetes node preparation complete!"
echo "==========================================================="
echo "You can now proceed with initializing the Kubernetes cluster."
echo "For master nodes, use:"
echo "  kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=<YOUR_IP>"
echo "For worker nodes, use the join command provided by the master."
echo "==========================================================="
