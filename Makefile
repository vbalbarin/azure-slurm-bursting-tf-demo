PYTHON := $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
CHECKOV := $(if $(wildcard .venv/bin/checkov),.venv/bin/checkov,checkov)

.PHONY: validate bicep-validate terraform-fmt terraform-init terraform-validate terraform-test bootstrap-init bootstrap-test backend-contract-test backend-evidence-test policy-test end-to-end-unit python-test python-type python-security chef-style chef-unit chef-integration

validate: bicep-validate terraform-fmt terraform-validate terraform-test bootstrap-test backend-contract-test backend-evidence-test policy-test end-to-end-unit python-type python-security python-test

bicep-validate:
	az bicep build --file infra/cyclecloud/main.bicep --stdout >/dev/null
	bash -n infra/cyclecloud/bootstrap.sh
	bash -n tests/end-to-end/cyclecloud_stack.sh
	bash -n tests/end-to-end/finalize_provisioning.sh
	bash -n tests/end-to-end/generate_cyclecloud_bootstrap_secrets.sh
	bash -n tests/end-to-end/key_vault_reconciliation.sh
	bash -n tests/end-to-end/store_admin_secrets.sh

terraform-fmt:
	terraform -chdir=terraform fmt -check -recursive

terraform-init:
	terraform -chdir=terraform init -backend=false
	terraform -chdir=terraform/capacity-probe init -backend=false

bootstrap-init:
	terraform -chdir=terraform/bootstrap init -backend=false

terraform-validate: terraform-init bootstrap-init
	terraform -chdir=terraform validate
	terraform -chdir=terraform/capacity-probe validate
	terraform -chdir=terraform/bootstrap validate
	command -v tflint >/dev/null || { echo "tflint is required" >&2; exit 1; }
	tflint --chdir=terraform
	tflint --chdir=terraform/bootstrap
	command -v $(CHECKOV) >/dev/null || { echo "checkov is required" >&2; exit 1; }
	$(CHECKOV) -d terraform

terraform-test: terraform-init
	terraform -chdir=terraform test -test-directory=tests
	terraform -chdir=terraform/capacity-probe test

bootstrap-test: bootstrap-init
	terraform -chdir=terraform/bootstrap test

backend-contract-test:
	$(PYTHON) -m pytest tests/end-to-end/test_backend_state_contracts.py

backend-evidence-test:
	$(PYTHON) -m pytest tests/end-to-end/test_backend_migration_evidence.py tests/end-to-end/test_backend_live_acceptance_evidence.py

policy-test:
	$(PYTHON) -m pytest tests/policy

end-to-end-unit:
	$(PYTHON) -m pytest tests/end-to-end/test_preflight.py tests/end-to-end/test_verify_inventory.py tests/end-to-end/test_capacity_probe.py tests/end-to-end/test_provision.py tests/end-to-end/test_cyclecloud_stack.py tests/end-to-end/test_key_vault_reconciliation.py tests/end-to-end/test_export_preflight_env.py tests/end-to-end/test_marketplace_terms.py tests/end-to-end/test_render_preflight_summary.py

python-test:
	PYTHONPATH=tools/headless_template/src $(PYTHON) -m pytest tools/headless_template/tests

python-type:
	$(PYTHON) -m mypy tools/headless_template/src

python-security:
	$(PYTHON) -m bandit -c tools/headless_template/pyproject.toml -r tools/headless_template/src

chef-style:
	BUNDLE_GEMFILE=chef/Gemfile bundle exec cookstyle chef

chef-unit:
	BUNDLE_GEMFILE=chef/Gemfile bundle exec rspec chef/cookbooks/*/spec/unit

chef-integration:
	cd chef && BUNDLE_GEMFILE=Gemfile bundle exec kitchen test
