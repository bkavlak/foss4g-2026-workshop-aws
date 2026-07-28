# Orchestration only. Every target is a thin, explicit sequence of the tools
# below; no logic lives here that belongs in a module.

-include .env
export

REGION      ?= $(AWS_REGION)

# OpenTofu reads var.region; the AWS CLI reads --region. Deriving both from the
# single AWS_REGION in .env stops `tofu apply` building in one region while
# `make image-push` authenticates against another -- a mismatch whose error
# messages never mention regions.
ifneq ($(strip $(REGION)),)
export TF_VAR_region := $(REGION)
endif
PARTICIPANTS?= 5
IMAGE_TAG   ?= v1
TOFU        := tofu -chdir=infra
UV          := uv
PREFLIGHT   := ./scripts/preflight.sh

# Every tool in .tool-versions, by the short name asdf knows it as. Verified to
# exist in the asdf plugin registry.
ASDF_PLUGINS := python uv opentofu helm kubectl awscli pre-commit

.DEFAULT_GOAL := help
.PHONY: help doctor setup lint typecheck security test test-infra check hooks \
        roster image-build image-push data-push plan up down url clean

help: ## Show available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

doctor: ## Report which required tools are missing, and how to install them
	@$(PREFLIGHT)

setup: ## Install the toolchain (asdf), the Python env (uv) and the git hooks
	@command -v asdf >/dev/null 2>&1 || { \
	  echo "asdf is not installed. It is what installs the tools this repo needs."; \
	  echo "  macOS:  brew install asdf"; \
	  echo "  other:  https://asdf-vm.com/guide/getting-started.html"; \
	  echo "Then open a new terminal and run 'make setup' again."; \
	  exit 1; }
	@# A bare `asdf install` is a silent no-op when the plugins have not been
	@# added: it exits 0 having installed nothing, and the next command fails
	@# with "tofu: No such file or directory". Add them first, every time --
	@# adding one that is already present is harmless.
	@for plugin in $(ASDF_PLUGINS); do \
	  printf '  plugin %s\n' "$$plugin"; \
	  asdf plugin add $$plugin >/dev/null 2>&1 || true; \
	done
	@echo "Installing pinned versions (building Python takes a few minutes)..."
	asdf install
	@# Prove it worked, so setup cannot succeed while leaving tools missing.
	@$(PREFLIGHT) tofu helm kubectl aws uv
	$(UV) sync --all-groups
	@# `pre-commit install` fails outright outside a git repository, which would
	@# otherwise abort setup at the very end, after several minutes of installs.
	@# The hooks are worth having, but nothing else here depends on them.
	@if git rev-parse --git-dir >/dev/null 2>&1; then \
	  $(UV) run pre-commit install; \
	else \
	  echo "Not a git repository, so the git hooks were skipped."; \
	  echo "To enable them:  git init && uv run pre-commit install"; \
	fi
	helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ >/dev/null
	helm repo update >/dev/null
	helm dependency build charts/workshop

lint: ## Style and correctness, no cloud account needed
	@$(PREFLIGHT) uv helm tofu
	$(UV) run ruff check .
	$(UV) run ruff format --check .
	$(UV) run pylint --rcfile=.pylintrc src tests \
	  charts/workshop/files/roster_authenticator.py
	helm lint charts/workshop
	$(TOFU) fmt -check -recursive
	$(TOFU) validate

typecheck: ## mypy, strict over src/
	$(UV) run mypy

security: ## Python and infrastructure security scanners
	$(UV) run bandit -c pyproject.toml -r src charts/workshop/files
	$(UV) run checkov --config-file .checkov.yaml

hooks: ## Run every pre-commit hook over the whole tree
	$(UV) run pre-commit run --all-files --hook-stage pre-commit
	$(UV) run pre-commit run --all-files --hook-stage pre-push

test: ## Python + chart-render tests (fully offline)
	$(UV) run pytest -q

test-infra: ## OpenTofu unit tests against mocked providers (no AWS calls)
	@$(PREFLIGHT) tofu
	$(TOFU) test

check: lint typecheck security test test-infra ## Everything that runs without AWS credentials

roster: ## Mint participant credentials into roster/ (run once per workshop)
	$(UV) run workshop provision --participants $(PARTICIPANTS) --directory roster

image-build: ## Build the GDAL + Python participant image
	@$(PREFLIGHT) docker
	docker build -t workshop-participant:$(IMAGE_TAG) docker

image-push: image-build ## Push the image to the ECR repository created by tofu
	$(eval REPO := $(shell $(TOFU) output -raw image_repository))
	@# ECR tags are immutable, so re-pushing an existing tag is refused by AWS
	@# with a message that does not explain itself. Say what to do instead.
	@if aws ecr describe-images --region $(REGION) \
	     --repository-name $(notdir $(REPO)) \
	     --image-ids imageTag=$(IMAGE_TAG) >/dev/null 2>&1; then \
	  echo "ERROR: $(IMAGE_TAG) already exists in ECR and tags are immutable."; \
	  echo "       Rebuild under a new tag:  make up IMAGE_TAG=v2"; \
	  exit 1; \
	fi
	aws ecr get-login-password --region $(REGION) \
	  | docker login --username AWS --password-stdin $(firstword $(subst /, ,$(REPO)))
	docker tag workshop-participant:$(IMAGE_TAG) $(REPO):$(IMAGE_TAG)
	docker push $(REPO):$(IMAGE_TAG)

data-push: ## Mirror ./data into the workshop S3 bucket
	$(eval BUCKET := $(shell $(TOFU) output -raw dataset_uri))
	aws s3 sync data/ $(BUCKET)/ --delete --region $(REGION)

plan: ## Show what an apply would change
	@$(PREFLIGHT) tofu aws
	$(TOFU) plan -var participant_count=$(PARTICIPANTS) -var image_tag=$(IMAGE_TAG)

up: ## Bring the workshop online (staged: registry+bucket, then payload, then cluster)
	@$(PREFLIGHT)
	$(TOFU) init
	$(TOFU) apply -target=module.registry -target=module.dataset -auto-approve \
	  -var participant_count=$(PARTICIPANTS) -var image_tag=$(IMAGE_TAG)
	$(MAKE) image-push data-push
	$(TOFU) apply -var participant_count=$(PARTICIPANTS) -var image_tag=$(IMAGE_TAG)

url: ## Print the URL participants should open
	@$(PREFLIGHT) kubectl
	kubectl -n workshop get svc proxy-public \
	  -o jsonpath='http://{.status.loadBalancer.ingress[0].hostname}{"\n"}'

down: ## Destroy every billable resource
	@$(PREFLIGHT) tofu aws
	$(TOFU) destroy -var participant_count=$(PARTICIPANTS) -var image_tag=$(IMAGE_TAG)

clean: ## Remove local build artefacts (never touches roster/ or data/)
	rm -rf .pytest_cache .ruff_cache charts/workshop/charts charts/workshop/Chart.lock
