# Image URL to use all building/pushing image targets
IMG ?= jobttlcontroller:latest

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test suite.
SHELL = /usr/bin/env bash -o pipefail

all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking at lines that
# consist of a single word followed by a colon, and then looking at the next
# line to determine if it starts with "##". If so, it prints the word and the
# description.
.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: ## Generate manifests e.g. CRD, RBAC etc.
	@echo "Manifests are already generated in manifests/ directory"

.PHONY: generate
generate: ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	@echo "No code generation needed for this project"

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet ## Run tests.
	go test ./... -coverprofile cover.out

##@ Build


.PHONY: build
build: generate fmt vet ## Build manager binary for host architecture.
	go build -o bin/manager main.go

.PHONY: build-amd64
build-amd64: generate fmt vet ## Build manager binary for amd64.
	GOOS=linux GOARCH=amd64 go build -o bin/manager-amd64 main.go

.PHONY: build-arm64
build-arm64: generate fmt vet ## Build manager binary for arm64.
	GOOS=linux GOARCH=arm64 go build -o bin/manager-arm64 main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go --target-ttl=3600 --label-selector="ttl-controller=enabled"


.PHONY: docker-build
docker-build: test ## Build docker image with the manager (default arch).
	docker build -t ${IMG} .

.PHONY: docker-buildx
docker-buildx: test ## Build and push multi-arch docker image (amd64 and arm64).
	docker buildx build --platform linux/amd64,linux/arm64 -t ${IMG} --push .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}

##@ Deployment

.PHONY: install
install: manifests ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	kubectl apply -f manifests/

.PHONY: uninstall
uninstall: manifests ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	kubectl delete -f manifests/

.PHONY: deploy
deploy: manifests ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd manifests && kustomize edit set image controller=${IMG}
	kubectl apply -f manifests/

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config.
	kubectl delete -f manifests/

CONTROLLER_GEN = $(shell pwd)/bin/controller-gen
.PHONY: controller-gen
controller-gen: ## Download controller-gen locally if necessary.
	$(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.11.3)

KUSTOMIZE = $(shell pwd)/bin/kustomize
.PHONY: kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v4@v4.5.7)

# go-get-tool will 'go get' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin go install $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef
