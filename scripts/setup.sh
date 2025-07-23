#!/bin/bash

# JobTTLController Setup Script
# This script helps set up the JobTTLController webhook in a Kubernetes cluster

set -e

# Configuration
NAMESPACE="job-ttl-system"
SERVICE_NAME="job-ttl-webhook-service"
WEBHOOK_NAME="job-ttl-webhook-config"
IMAGE="jobttlcontroller:latest"
CERT_DIR="/tmp/k8s-webhook-server/serving-certs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if kubectl is available
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log "Prerequisites check passed"
}

# Create namespace
create_namespace() {
    log "Creating namespace ${NAMESPACE}..."
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
}

# Generate certificates for webhook
generate_certs() {
    log "Generating certificates for webhook..."
    
    # Create temp directory
    mkdir -p ${CERT_DIR}
    
    # Generate CA private key
    openssl genrsa -out ${CERT_DIR}/ca-key.pem 2048
    
    # Generate CA certificate
    openssl req -new -x509 -days 3650 -key ${CERT_DIR}/ca-key.pem -out ${CERT_DIR}/ca-cert.pem \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=job-ttl-ca"
    
    # Generate server private key
    openssl genrsa -out ${CERT_DIR}/server-key.pem 2048
    
    # Generate server certificate request
    openssl req -new -key ${CERT_DIR}/server-key.pem -out ${CERT_DIR}/server-req.pem \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${SERVICE_NAME}.${NAMESPACE}.svc"
    
    # Create extensions file
    cat > ${CERT_DIR}/server-ext.cnf <<EOF
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${SERVICE_NAME}
DNS.2 = ${SERVICE_NAME}.${NAMESPACE}
DNS.3 = ${SERVICE_NAME}.${NAMESPACE}.svc
DNS.4 = ${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local
EOF
    
    # Generate server certificate
    openssl x509 -req -days 3650 -in ${CERT_DIR}/server-req.pem \
        -CA ${CERT_DIR}/ca-cert.pem -CAkey ${CERT_DIR}/ca-key.pem \
        -CAcreateserial -out ${CERT_DIR}/server-cert.pem \
        -extfile ${CERT_DIR}/server-ext.cnf
    
    # Create Kubernetes secret
    kubectl create secret tls webhook-server-cert \
        --cert=${CERT_DIR}/server-cert.pem \
        --key=${CERT_DIR}/server-key.pem \
        -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Get CA bundle for webhook configuration
    CA_BUNDLE=$(base64 -w 0 ${CERT_DIR}/ca-cert.pem)
    
    # Update webhook configuration with CA bundle
    sed "s/LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUJJREFOQmdrcWhraUc5dzBCQVFFRkFBT0NBUThBTUlJQkNnS0NBUUVBMW5TNGhJV3YyYVpNMEl5T3Y4YWMKV2dLckJCZEtXT2F5NG5zQ25xb1Z2Z3V1b2I2KzZudHF4Mmt6WmlSZDlJcnVnazk5YVJ2dk5uczN0a3RBZQowdkV3WURxWUxhZ3h1WnE5b0xYN2x3K1dpaUU4Y3ZGK3NqY3ZXVXF0VzF0YXYzRFF4Wk9GN2dYcG5EClF5eG5uSjZHRzFaRDE0dU8xVlN4Z2JTMmhqL1hFRkJ6eTJxS3hRWWJ6UlpqUkVhRU5zT1l5STJ4aGUKdGlVQUk3S3hZUk5hU1lWNzZoUkpGWHpYV2V1Z2E5UVVHWnJ4NVhqeFdlUTdXOWRjdzVoYW5udk9wR3gKc3dXTk1VeG9YcXlBV2R3N3dTWFhGSTVlK2Q2czVlYkVjMXhVTW1Ia2l5bHNHTklMM1l4dm5UTlFUMgpnd2JlZ1d3SURBUUFCCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K/${CA_BUNDLE}/g" manifests/webhook-configuration.yaml > manifests/webhook-configuration-updated.yaml
    
    log "Certificates generated and secret created"
}

# Build and load Docker image
build_and_load() {
    log "Building Docker image..."
    docker build -t ${IMAGE} .
    
    log "Loading image into cluster..."
    if command -v kind &> /dev/null; then
        kind load docker-image ${IMAGE}
    elif command -v minikube &> /dev/null; then
        minikube image load ${IMAGE}
    else
        warn "Neither kind nor minikube detected. Please ensure the image is available in your cluster."
    fi
}

# Deploy the controller
deploy_controller() {
    log "Deploying JobTTLController..."
    
    # Apply RBAC
    kubectl apply -f manifests/rbac.yaml
    
    # Apply deployment
    kubectl apply -f manifests/deployment.yaml
    
    # Apply webhook configuration
    kubectl apply -f manifests/webhook-configuration-updated.yaml
    
    log "JobTTLController deployed successfully"
}

# Wait for deployment to be ready
wait_for_deployment() {
    log "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/job-ttl-controller -n ${NAMESPACE}
}

# Main setup function
main() {
    log "Starting JobTTLController setup..."
    
    check_prerequisites
    create_namespace
    generate_certs
    build_and_load
    deploy_controller
    wait_for_deployment
    
    log "Setup complete! JobTTLController is now running."
    log "You can test it by creating a Job with the label 'ttl-controller=enabled'"
    log "Example: kubectl apply -f test-job.yaml"
}

# Cleanup function
cleanup() {
    log "Cleaning up JobTTLController..."
    kubectl delete -f manifests/webhook-configuration-updated.yaml --ignore-not-found=true
    kubectl delete -f manifests/deployment.yaml --ignore-not-found=true
    kubectl delete -f manifests/rbac.yaml --ignore-not-found=true
    kubectl delete namespace ${NAMESPACE} --ignore-not-found=true
    rm -rf ${CERT_DIR}
    rm -f manifests/webhook-configuration-updated.yaml
    log "Cleanup complete"
}

# Handle command line arguments
case "$1" in
    "setup")
        main
        ;;
    "cleanup")
        cleanup
        ;;
    *)
        echo "Usage: $0 {setup|cleanup}"
        echo "  setup   - Deploy JobTTLController to the cluster"
        echo "  cleanup - Remove JobTTLController from the cluster"
        exit 1
        ;;
esac
