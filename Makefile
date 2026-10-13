.PHONY: validate terraform-fmt terraform-init terraform-validate terraform-test policy-test end-to-end-unit python-test python-type python-security chef-style chef-unit chef-integration

validate: terraform-fmt terraform-validate terraform-test policy-test end-to-end-unit python-type python-security python-test

terraform-fmt:
	terraform -chdir=terraform fmt -check -recursive

terraform-init:
	terraform -chdir=terraform init -backend=false

terraform-validate: terraform-init
	terraform -chdir=terraform validate
	terraform -chdir=terraform/capacity-probe init -backend=false
	terraform -chdir=terraform/capacity-probe validate
	command -v tflint >/dev/null || { echo "tflint is required" >&2; exit 1; }
	tflint --chdir=terraform
	command -v checkov >/dev/null || { echo "checkov is required" >&2; exit 1; }
	checkov -d terraform

terraform-test: terraform-init
	terraform -chdir=terraform test -test-directory=tests

policy-test:
	python3 -m pytest tests/policy

end-to-end-unit:
	python3 -m pytest tests/end-to-end/test_preflight.py tests/end-to-end/test_verify_inventory.py tests/end-to-end/test_capacity_probe.py tests/end-to-end/test_provision.py tests/end-to-end/test_export_preflight_env.py tests/end-to-end/test_marketplace_terms.py tests/end-to-end/test_render_preflight_summary.py

python-test:
	PYTHONPATH=tools/headless_template/src python3 -m pytest tools/headless_template/tests

python-type:
	python3 -m mypy tools/headless_template/src

python-security:
	python3 -m bandit -c tools/headless_template/pyproject.toml -r tools/headless_template/src

chef-style:
	BUNDLE_GEMFILE=chef/Gemfile bundle exec cookstyle chef

chef-unit:
	BUNDLE_GEMFILE=chef/Gemfile bundle exec rspec chef/cookbooks/*/spec/unit

chef-integration:
	cd chef && BUNDLE_GEMFILE=Gemfile bundle exec kitchen test
