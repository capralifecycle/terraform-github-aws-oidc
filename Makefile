TERRAFORM_DOCS_IMAGE_NAME=quay.io/terraform-docs/terraform-docs
TERRAFORM_DOCS_IMAGE_TAG=sha256:37329e2dc2518e7f719a986a3954b10771c3fe000f50f83fd4d98d489df2eae2
TERRAFORM_DOCS_IMAGE="${TERRAFORM_DOCS_IMAGE_NAME}@${TERRAFORM_DOCS_IMAGE_TAG}"

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
lint:
	tflint --format compact

.PHONY: lint-fix
lint-fix:
	tflint --fix

docs:
	docker run --rm --volume "$(shell pwd):/terraform-docs" \
  -u $(shell id -u) $(TERRAFORM_DOCS_IMAGE) /terraform-docs

docs-check:
	docker run --rm --volume "$(shell pwd):/terraform-docs" \
	-u $(shell id -u) $(TERRAFORM_DOCS_IMAGE) --output-check /terraform-docs

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
	tflint --init
