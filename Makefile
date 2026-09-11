.DEFAULT_GOAL := help
.PHONY: help check test test-suite

help: ## Show available commands
	@echo "  check       Unit tests + examples/basic.ahk"
	@echo "  test        Same as check"
	@echo "  test-suite  JSONTestSuite (318 files)"

check: ## Unit tests and CI example
	powershell -NoProfile -ExecutionPolicy Bypass -File test/check.ps1

test: check ## Alias for check

test-suite: ## nst/JSONTestSuite parsing samples
	powershell -NoProfile -ExecutionPolicy Bypass -File test/check.ps1 -Suite
