# Goose observability tutorial — one-liner targets wrapping scripts/.
# Every target is idempotent and reads configuration from .env (copy .env.example).
#
# Usage:  make <target>     e.g.  make deploy-collector
#         make help         list targets

SHELL := /bin/bash

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

.PHONY: provision
provision: ## (optional) Provision a cluster — see cluster/README.md
	./scripts/00-provision-cluster.sh

.PHONY: operators
operators: ## Install OpenTelemetry + Dynatrace operators (and DynaKube)
	./scripts/01-install-operators.sh

.PHONY: deploy-collector
deploy-collector: ## Deploy the logs DaemonSet + gateway StatefulSet collectors
	./scripts/02-deploy-collector.sh

.PHONY: deploy-goose
deploy-goose: ## Deploy Goose (namespace + config + deployment)
	./scripts/03-deploy-goose.sh

.PHONY: simple-agent
simple-agent: ## Run the simple single-recipe agent
	./scripts/04-run-simple-agent.sh

.PHONY: wire-mcp
wire-mcp: ## Enable the Dynatrace + GitHub MCP extensions
	./scripts/05-wire-mcp.sh

.PHONY: crew
crew: ## Run the in-process goosetown BMAD-style crew (default)
	./scripts/06-run-bmad-crew.sh

.PHONY: bmad-crew-acp
bmad-crew-acp: ## Deploy the per-role BMAD crew over ACP + launch the conductor
	./scripts/09-deploy-bmad-crew.sh

.PHONY: goosetown
goosetown: ## Deploy goosetown (orchestration + real-time dashboard UI)
	./scripts/10-deploy-goosetown.sh

.PHONY: review-pr
review-pr: ## Review a pull request (PR=<number>, empty = latest open PR)
	./scripts/08-review-pr.sh $(PR)

.PHONY: dashboards
dashboards: ## Publish the Dynatrace dashboards
	./scripts/07-apply-dashboards.sh

.PHONY: all
all: operators deploy-collector deploy-goose dashboards ## Full stack: operators → collector → goose → dashboards

.PHONY: teardown
teardown: ## Remove crew, Goose, collectors and namespace
	./scripts/99-teardown.sh
