.PHONY: up down fmt validate

up:
	./scripts/up.sh

down:
	./scripts/down.sh

fmt:
	tofu fmt -recursive || terraform fmt -recursive

validate:
	python3 scripts/validate-registry.py
