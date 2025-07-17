# Define phony targets to ensure Make doesn't look for files named after these targets.
.PHONY: run-bq-review setup help

all: help

# Run Code QA Review
# This target runs the 'bq-code-review' pre-commit hook on all files.
qa:
	@echo "--------------------------------------------------------"
	pre-commit run --all-files bq-code-review
	@echo "--------------------------------------------------------"
	@echo "Finished running 'bq-code-review'."

# This target insalls and updates pre-commit hooks locally.
setup:
	@echo "Installing pre-commit hooks locally..."
	pre-commit install
	pre-commit autoupdate
	@echo "Pre-commit hooks installed and updated."

ec:
	@echo "Empty commit to trigger pre-commit hooks."
	git commit --allow-empty -m "Empty-Commit"
	@echo "Pre-commit hooks executed."

# Target: help
# Description: Displays available make commands and their usage.
help:
	@echo "Usage:"
	@echo "  make                                - Display this help message."
	@echo "  make qa                             - Explicitly run the 'bq-code-review' pre-commit hook on all files."
	@echo "  make setup                          - Install and update pre-commit hooks locally."
	@echo "  make help                           - Display this help message."
	@echo ""
	@echo "Prerequisites:"
	@echo "  - pre-commit package must be installed (e.g., 'pip install pre-commit')."
	@echo "  - Your project must have a '.pre-commit-config.yaml' file configured"
	@echo "    with an entry for 'bq-code-review'."
