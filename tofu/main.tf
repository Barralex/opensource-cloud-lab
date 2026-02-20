# Open Source Cloud Lab - OpenTofu Configuration

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Token is configured via environment variable: DIGITALOCEAN_TOKEN
# NEVER hardcode credentials here
provider "digitalocean" {}

# =============================================================================
# VPC - Private Network (FREE)
# =============================================================================
# Nodes communicate through this internal network
# No ports exposed to public internet

resource "digitalocean_vpc" "main" {
  name        = "${var.project_name}-vpc-${var.environment}"
  region      = var.region
  ip_range    = "10.20.10.0/24"
  description = "Private network for K3s cluster"
}

# =============================================================================
# SSH Key - For secure access to droplets
# =============================================================================

resource "digitalocean_ssh_key" "default" {
  name       = "${var.project_name}-key-${var.environment}"
  public_key = file(var.ssh_public_key_path)
}

# =============================================================================
# Droplet - K3s Server (Control Plane + Worker)
# =============================================================================
# Single node for dev environment - runs everything

resource "digitalocean_droplet" "k3s_server" {
  name     = "${var.project_name}-k3s-${var.environment}"
  region   = var.region
  size     = "s-2vcpu-4gb"
  image    = "ubuntu-24-04-x64"
  vpc_uuid = digitalocean_vpc.main.id
  ssh_keys = [digitalocean_ssh_key.default.fingerprint]

  tags = ["k3s", "server", var.environment]

  # cloud-init script - runs on first boot
  user_data = <<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/cloud-init-output.log) 2>&1

    echo "=== Starting cloud-init setup ==="

    # Update system and install docker
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
    systemctl enable docker
    systemctl start docker

    # Install K3s (single node server)
    echo "=== Installing K3s ==="
    curl -sfL https://get.k3s.io | sh -s - \
      --disable traefik \
      --write-kubeconfig-mode 644

    # Wait for K3s to be ready
    echo "=== Waiting for K3s ==="
    until kubectl get nodes | grep -q "Ready"; do
      sleep 5
    done

    # Create namespaces
    echo "=== Creating namespaces ==="
    kubectl create namespace database --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace storage --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Install NGINX Ingress Controller
    echo "=== Installing NGINX Ingress ==="
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/baremetal/deploy.yaml

    # Patch NGINX to use hostNetwork (expose on node IP directly)
    kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
      --type='json' \
      -p='[{"op":"add","path":"/spec/template/spec/hostNetwork","value":true}]' || true

    # Wait for NGINX Ingress
    echo "=== Waiting for NGINX Ingress ==="
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=120s || true

    # Install PostgreSQL
    echo "=== Installing PostgreSQL ==="
    cat <<'PGEOF' | kubectl apply -f -
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: postgresql-data
      namespace: database
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 5Gi
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: postgresql-secret
      namespace: database
    type: Opaque
    stringData:
      POSTGRES_USER: stresslab
      POSTGRES_PASSWORD: stresslab123
      POSTGRES_DB: stress_lab
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: postgresql
      namespace: database
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: postgresql
      template:
        metadata:
          labels:
            app: postgresql
        spec:
          containers:
            - name: postgresql
              image: postgres:16-alpine
              ports:
                - containerPort: 5432
              envFrom:
                - secretRef:
                    name: postgresql-secret
              volumeMounts:
                - name: data
                  mountPath: /var/lib/postgresql/data
              resources:
                requests:
                  memory: "128Mi"
                  cpu: "100m"
                limits:
                  memory: "512Mi"
                  cpu: "500m"
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: postgresql-data
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: postgresql
      namespace: database
    spec:
      selector:
        app: postgresql
      ports:
        - port: 5432
          targetPort: 5432
    PGEOF

    # Install MinIO
    echo "=== Installing MinIO ==="
    cat <<'MINIOEOF' | kubectl apply -f -
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: minio-data
      namespace: storage
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 10Gi
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: minio-secret
      namespace: storage
    type: Opaque
    stringData:
      MINIO_ROOT_USER: admin
      MINIO_ROOT_PASSWORD: changeme123
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: minio
      namespace: storage
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: minio
      template:
        metadata:
          labels:
            app: minio
        spec:
          containers:
            - name: minio
              image: minio/minio:latest
              args: ["server", "/data", "--console-address", ":9001"]
              ports:
                - containerPort: 9000
                - containerPort: 9001
              envFrom:
                - secretRef:
                    name: minio-secret
              volumeMounts:
                - name: data
                  mountPath: /data
              resources:
                requests:
                  memory: "128Mi"
                  cpu: "100m"
                limits:
                  memory: "512Mi"
                  cpu: "500m"
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: minio-data
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: minio
      namespace: storage
    spec:
      selector:
        app: minio
      ports:
        - name: api
          port: 9000
          targetPort: 9000
        - name: console
          port: 9001
          targetPort: 9001
    MINIOEOF

    # Create MinIO bucket for stress-lab
    echo "=== Creating MinIO bucket ==="
    sleep 10
    kubectl run minio-init --namespace=storage --rm -i --restart=Never \
      --image=minio/mc:latest -- /bin/sh -c '
        mc alias set myminio http://minio:9000 admin changeme123 && \
        mc mb --ignore-existing myminio/stress-lab
      ' || true

    # Install Argo CD (may fail on some CRDs, but services will still work)
    echo "=== Installing Argo CD ==="
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true

    # Expose Argo CD with NodePort
    sleep 5
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort", "ports": [{"port": 443, "nodePort": 30080}]}}' || true

    # Wait for services to be ready
    echo "=== Waiting for services ==="
    kubectl wait --namespace database --for=condition=available deployment/postgresql --timeout=120s || true
    kubectl wait --namespace storage --for=condition=available deployment/minio --timeout=120s || true
    kubectl wait --namespace argocd --for=condition=available deployment/argocd-server --timeout=180s || true

    # Get Argo CD admin password
    ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    echo "Argo CD admin password: $ARGOCD_PASS" > /root/argocd-password.txt

    # Create marker file to indicate setup is complete
    touch /root/.k3s_installed
    touch /root/.infra_ready

    echo "=== Cloud-init setup complete ==="
    echo "Argo CD password saved to /root/argocd-password.txt"
  EOF
}

# =============================================================================
# Outputs - Useful info after apply
# =============================================================================

output "droplet_ip" {
  description = "Public IP of the K3s server"
  value       = digitalocean_droplet.k3s_server.ipv4_address
}

output "droplet_private_ip" {
  description = "Private IP (inside VPC)"
  value       = digitalocean_droplet.k3s_server.ipv4_address_private
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh root@${digitalocean_droplet.k3s_server.ipv4_address}"
}
