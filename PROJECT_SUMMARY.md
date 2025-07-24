# JobTTLController - Project Summary

## Overview
JobTTLController is a Kubernetes mutating admission webhook controller written in Go that automatically sets the `ttlSecondsAfterFinished` field for Jobs based on configurable label selectors.

## Project Structure
```
JobTTLController/
├── go.mod                          # Go module definition
├── go.sum                          # Go dependencies checksum
├── main.go                         # Main application entry point
├── Dockerfile                      # Container image build instructions
├── Makefile                        # Build and deployment automation
├── README.md                       # Comprehensive documentation
├── PROJECT_SUMMARY.md              # This file
├── test-job.yaml                   # Example Job for testing
├── scripts/
│   └── setup.sh                    # Automated setup script
├── internal/
│   └── webhook/
│       └── job_ttl_mutator.go      # Core webhook logic
├── manifests/
│   ├── deployment.yaml             # Controller deployment
│   ├── rbac.yaml                   # RBAC permissions
│   ├── webhook-configuration.yaml  # MutatingWebhookConfiguration
│   ├── cert-manager.yaml           # cert-manager integration
│   └── setup.sh                    # Setup automation
└── helm/
    └── jobttlcontroller/           # Helm chart for deployment
        ├── Chart.yaml              # Chart metadata
        ├── values.yaml             # Default values
        └── templates/              # Template files
            ├── _helpers.tpl        # Template helpers
            ├── deployment.yaml     # Deployment template
            ├── rbac.yaml           # RBAC template
            ├── service.yaml        # Service template
            ├── serviceaccount.yaml # ServiceAccount template
            └── webhook.yaml        # Webhook configuration
```

## Key Components

### 1. Core Logic (`internal/webhook/job_ttl_mutator.go`)
- **JobTTLMutator**: Main webhook handler struct
- **Label-based filtering**: Uses Kubernetes label selectors to target specific Jobs
- **JSON Patch operations**: Creates RFC 6902 compliant patches for TTL modification
- **Admission handling**: Implements Kubernetes admission webhook interface

### 2. Configuration
- **Target TTL**: Configurable via `--target-ttl` flag (default: 3600 seconds)
- **Label Selector**: Configurable via `--label-selector` flag (default: "")
- **TLS Certificates**: Configurable via `--cert-dir` flag

### 3. Deployment Architecture
- **Namespace**: `job-ttl-system`
- **Service**: `job-ttl-webhook-service`
- **Deployment**: Single replica with resource limits
- **RBAC**: Minimal required permissions for Job access

## Usage Examples

### Basic Usage
```bash
# Deploy with default settings (3600s TTL, no label filtering)
kubectl apply -f manifests/

# Deploy with custom TTL and label selector
kubectl apply -f manifests/
kubectl patch deployment job-ttl-controller -n job-ttl-system -p '{"spec":{"template":{"spec":{"containers":[{"name":"manager","args":["--target-ttl=7200","--label-selector=environment=production"]}]}}}}'
```

### Testing
```bash
# Create a test job
kubectl apply -f test-job.yaml

# Verify TTL was set
kubectl get job test-job-with-ttl -o yaml | grep ttlSecondsAfterFinished
```

## Security Features
- **TLS encryption**: All webhook communication uses HTTPS
- **RBAC least privilege**: Minimal required permissions
- **Non-root containers**: Runs as user 65532:65532
- **Resource limits**: CPU/memory constraints applied

## Deployment Options

### 1. Manual Deployment
```bash
# Build and push image
make docker-build IMG=your-registry/jobttlcontroller:latest
make docker-push IMG=your-registry/jobttlcontroller:latest

# Deploy manifests
kubectl apply -f manifests/
```

### 2. Helm Chart Deployment (Recommended)
```bash
# Add the Helm repository (if not already added)
helm repo add jobttlcontroller https://dheeth.github.io/jobttlcontroller

# Install the chart
helm install jobttl-fix jobttlcontroller \
  --namespace jobttlcontroller-system \
  --create-namespace \
  --set controller.targetTTL=100 \
  --set controller.labelSelector="ttl-controller=enabled"

# Upgrade the chart
helm upgrade jobttl-fix jobttlcontroller \
  --namespace jobttlcontroller-system

# Uninstall the chart
helm uninstall jobttl-fix --namespace jobttlcontroller-system
```

### 3. Automated Setup (Alternative)
```bash
# Full automated setup with certificates
./scripts/setup.sh setup

# Cleanup
./scripts/setup.sh cleanup
```

### 4. cert-manager Integration
```bash
# Install cert-manager first
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Apply cert-manager manifests
kubectl apply -f manifests/cert-manager.yaml
kubectl apply -f manifests/
```

## Helm Chart Features

The JobTTLController Helm chart provides a comprehensive and flexible deployment solution with the following features:

### Chart Configuration
- **Values**: Configurable through `values.yaml` or command-line `--set` parameters
- **Customization**: All aspects of the deployment can be customized
- **Defaults**: Sensible defaults for production use

### Key Configuration Parameters
| Parameter | Default | Description |
|-----------|---------|-------------|
| `replicaCount` | 1 | Number of controller replicas |
| `image.repository` | jobttlcontroller | Container image repository |
| `image.tag` | latest | Container image tag |
| `controller.targetTTL` | 100 | Target TTL in seconds |
| `controller.labelSelector` | "" | Label selector for job filtering |
| `certificates.generate` | true | Whether to generate certificates |
| `metrics.enabled` | true | Enable metrics endpoint |

### Certificate Management
- **Automatic Generation**: The chart can automatically generate TLS certificates using cert-manager
- **Custom Certificates**: Support for providing your own certificates
- **Self-signed Issuer**: Built-in self-signed certificate issuer

### Security
- **Pod Security Context**: Runs with non-root user and restricted permissions
- **Security Context**: Container runs with dropped capabilities and read-only filesystem
- **RBAC**: Minimal required permissions with ClusterRole and ClusterRoleBinding

### Resource Management
- **Resource Limits**: CPU and memory limits configured
- **Node Affinity**: Support for node selectors, tolerations, and affinity rules
- **Health Checks**: Liveness and readiness probes configured

### Multi-Architecture Support
- **AMD64 & ARM64**: The chart works with multi-architecture container images
- **Platform Detection**: Automatically detects and uses the appropriate image

The Helm chart is the recommended deployment method as it provides the most flexibility and ease of use.

## Configuration Parameters

| Parameter | Flag | Default | Description |
|-----------|------|---------|-------------|
| Target TTL | `--target-ttl` | 100 | TTL in seconds after job completion |
| Label Selector | `--label-selector` | "" | Label selector for job filtering |
| Cert Directory | `--cert-dir` | "/tmp/k8s-webhook-server/serving-certs" | TLS certificate directory |
| Metrics Port | `--metrics-bind-address` | ":8080" | Prometheus metrics endpoint |
| Health Port | `--health-probe-bind-address` | ":8081" | Health check endpoint |

## Monitoring and Debugging

### Check Controller Status
```bash
kubectl get pods -n job-ttl-system
kubectl logs -n job-ttl-system deployment/job-ttl-controller
```

### Verify Webhook Registration
```bash
kubectl get mutatingwebhookconfigurations job-ttl-webhook-config
```

### Test Webhook Functionality
```bash
# Create test job
kubectl apply -f test-job.yaml

# Check if TTL was applied
kubectl get job test-job-with-ttl -o jsonpath='{.spec.ttlSecondsAfterFinished}'
```

## Development Workflow

### Local Development
```bash
# Format code
make fmt

# Run tests
make test

# Build binary
make build

# Run locally (requires kubeconfig)
make run
```

### Building Container
```bash
# Build image
make docker-build

# Push to registry
make docker-push
```

## Troubleshooting Guide

### Common Issues

1. **Webhook not responding**
   - Check pod status: `kubectl get pods -n job-ttl-system`
   - Check logs: `kubectl logs -n job-ttl-system deployment/job-ttl-controller`
   - Verify certificates: `kubectl get secret webhook-server-cert -n job-ttl-system`

2. **Jobs not getting TTL**
   - Check label selector: `kubectl get jobs --show-labels`
   - Verify webhook registration: `kubectl get mutatingwebhookconfigurations`
   - Check controller logs for admission requests

3. **Permission denied errors**
   - Verify RBAC: `kubectl auth can-i get jobs --as=system:serviceaccount:job-ttl-system:job-ttl-controller`

## Performance Considerations
- **Resource usage**: ~100m CPU, 64Mi memory (configurable)
- **Latency**: <10ms webhook response time
- **Scalability**: Single replica sufficient for most clusters
- **Availability**: Can be scaled horizontally if needed

## Future Enhancements
- Support for namespace-specific TTL configurations
- ConfigMap-based dynamic configuration
- Prometheus metrics for TTL operations
- Dry-run mode for testing
- Support for CronJob TTL management

## License
MIT License - see LICENSE file for details
