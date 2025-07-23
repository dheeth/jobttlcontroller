# JobTTLController

A Kubernetes controller that uses a mutating webhook to automatically set the `ttlSecondsAfterFinished` field for Jobs based on label selectors.

## Overview

JobTTLController is a Kubernetes admission webhook that intercepts Job creation and updates, and patches the `ttlSecondsAfterFinished` field to a specified value for Jobs that match the configured label selector.

## Features

- **Label-based filtering**: Only applies TTL to Jobs that match the specified label selector. If not provided, it'll patch all jobs that do not have the ttlSecondsAfterFinished same as target TTL value.
- **Configurable TTL**: Set the target TTL value via command-line arguments
- **Webhook-based**: Uses Kubernetes mutating admission webhooks for seamless integration
- **Lightweight**: Minimal resource footprint with efficient processing

## Quick Start

### Prerequisites

- Kubernetes cluster (1.16+)
- kubectl configured to access your cluster
- Docker (for building the image)
- cert-manager or manual certificate management for webhook TLS

### Installation

#### Option 1: Helm Chart (Recommended)
The easiest way to install JobTTLController is using the Helm chart:

```bash
# Add the Helm repository (if not already added)
helm repo add jobttlcontroller https://your-repo-url.com

# Install the chart
helm install jobttlcontroller helm/jobttlcontroller \
  --namespace jobttlcontroller-system \
  --create-namespace \
  --set controller.targetTTL=3600 \
  --set controller.labelSelector="ttl-controller=enabled"
```

#### Option 2: Manual Deployment
1. **Build the Docker image**:
   ```bash
   make docker-build IMG=your-registry/jobttlcontroller:latest
   make docker-push IMG=your-registry/jobttlcontroller:latest
   ```

2. **Deploy to Kubernetes**:
   ```bash
   # Update the image in deployment.yaml first
   kubectl apply -f manifests/
   ```

3. **Configure certificates**:
   The webhook requires TLS certificates. You can use cert-manager or manually create certificates.

### Configuration

The controller can be configured using command-line arguments:

- `--target-ttl`: Target TTL in seconds for jobs after they finish (default: 3600)
- `--label-selector`: Label selector to match jobs for TTL patching (default: "")
- `--cert-dir`: Directory containing TLS certificates (default: "/tmp/k8s-webhook-server/serving-certs")
- `--metrics-bind-address`: Address for metrics endpoint (default: ":8080")
- `--health-probe-bind-address`: Address for health probes (default: ":8081")

### Usage Examples

#### Example 1: Apply TTL to all Jobs in a namespace
```yaml
# Deploy the controller with label selector
kubectl apply -f manifests/
```

#### Example 2: Apply TTL to specific Jobs
Create Jobs with the label `ttl-controller=enabled`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: example-job
  labels:
    ttl-controller: enabled
spec:
  template:
    spec:
      containers:
      - name: example
        image: busybox
        command: ["echo", "Hello World"]
      restartPolicy: Never
```

#### Example 3: Custom TTL value
Deploy the controller with a custom TTL:

```yaml
# In manifests/deployment.yaml
args:
- --target-ttl=7200  # 2 hours
- --label-selector=environment=production
```

## Architecture

### Components

1. **Webhook Server**: Handles admission requests and patches Job specs
2. **MutatingWebhookConfiguration**: Registers the webhook with Kubernetes
3. **RBAC**: Service account and permissions for the controller

### Flow

1. Job is created or updated in the cluster
2. Kubernetes API server sends admission request to JobTTLController webhook
3. Controller checks if Job matches the label selector
4. If matched, controller patches the Job with the specified TTL
5. Job proceeds with creation/update

## Development

### Local Development

1. **Run locally** (requires kubeconfig):
   ```bash
   make run
   ```

2. **Build binary**:
   ```bash
   make build
   ```

3. **Run tests**:
   ```bash
   make test
   ```

### Building

```bash
# Build Docker image
make docker-build

# Push to registry
make docker-push
```

## Metrics

The JobTTLController exports the following Prometheus metrics on the metrics endpoint (default: `:8080/metrics`):

### Webhook Metrics
- `jobttlcontroller_webhook_requests_total{operation,result}`: Total number of webhook admission requests by operation (CREATE, UPDATE) and result (allowed, denied)
- `jobttlcontroller_webhook_jobs_patched_total`: Total number of Jobs that were patched with TTL values

### Job Metrics
- `jobttlcontroller_jobs_matching_selector_total`: Total number of Jobs matching the configured label selector
- `jobttlcontroller_jobs_ttl_set_total`: Total number of Jobs that had their TTL set
- `jobttlcontroller_jobs_ttl_already_set_total`: Total number of Jobs that already had the target TTL value

### Example Usage
To view the metrics:
```bash
# Port forward to the controller
kubectl port-forward -n job-ttl-system deployment/job-ttl-controller 8080:8080

# Access metrics endpoint
curl http://localhost:8080/metrics
```

## Troubleshooting

### Common Issues

1. **Webhook not working**: Check if certificates are properly configured
2. **Jobs not getting TTL**: Verify label selector matches Job labels
3. **Permission errors**: Ensure RBAC is properly configured
4. **Metrics not available**: Ensure the metrics endpoint is accessible and the controller has proper permissions

### Logging

The controller provides detailed logging for all operations. You can check the logs to see:

- When a Job matches or doesn't match the label selector
- When a Job already has the target TTL value
- When a Job has a different TTL value that will be updated
- When a Job has no TTL value that will be set
- When a Job's TTL is successfully set

### Debugging

```bash
# Check webhook configuration
kubectl get mutatingwebhookconfigurations job-ttl-webhook-config

# Check controller logs
kubectl logs -n job-ttl-system deployment/job-ttl-controller

# View detailed logs for specific operations
kubectl logs -n job-ttl-system deployment/job-ttl-controller | grep "jobttlcontroller"

# Test webhook
kubectl create -f test-job.yaml

# Check metrics
kubectl port-forward -n job-ttl-system deployment/job-ttl-controller 8080:8080
curl http://localhost:8080/metrics
```

## Security

- The webhook uses TLS for secure communication
- Minimal RBAC permissions are granted
- Runs as non-root user in the container

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
