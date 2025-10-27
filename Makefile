.PHONY: all
all: build

.PHONY: build
build: init fmt lint-fix docs validate

.PHONY: check
check: init fmt-check lint docs-check validate

.PHONY: init
init:
	terraform init

.PHONY: fmt
fmt:
	terraform fmt

.PHONY: fmt-check
fmt-check:
	terraform fmt -check

.PHONY: validate
validate:
	terraform validate

.PHONY: lint-init
lint-init:
	tflint --init

.PHONY: lint
lint: lint-init
	tflint --format compact

.PHONY: lint-fix
lint-fix: lint-init
	tflint --fix

.PHONY: upgrade-lockfile
upgrade-lockfile:
	terraform init -upgrade

.PHONY: release
release:
	npm ci
	npm run semantic-release

docs:
	terraform-docs .

docs-check:
	terraform-docs . --output-check

# extra checks intended to be run locally
.PHONY: extra-checks
extra-checks: lint-workflows lint-secrets audit-workflows docs-check

.PHONY: lint-workflows
lint-workflows:
	actionlint --oneline

.PHONY: lint-secrets
lint-secrets:
	gitleaks git --pre-commit --redact --staged --verbose --no-banner

.PHONY: audit-workflows
audit-workflows:
	zizmor .github/workflows --offline

.PHONY: install-tools
install-tools:
	mise install

.PHONY: validate-renovate
validate-renovate:
	npx --yes --package renovate -- renovate-config-validator --strict renovate.json5

.PHONY: upgrade-deps
upgrade-deps:
	npm run upgrade-dependencies

