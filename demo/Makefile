# demo/Makefile --- run the SDC provider + consumer + dashboard.
#
# All Python dependencies live in a uv-managed venv (.venv) created from
# pyproject.toml.  `uv run` transparently ensures the venv is synced.

UV ?= uv

.PHONY: demo data provider consumer venv sync clean

## venv     Create the uv-managed virtual environment (.venv)
venv:
	$(UV) venv --allow-existing

## sync     Install/refresh dependencies from pyproject.toml
sync:
	$(UV) sync

## demo     Start provider (background) and consumer/dashboard (foreground) on :8000
demo: sync data
	@echo "Starting SDC provider..."
	@$(UV) run python provider.py --data data/gaitband-sample.csv & \
	  echo $$! > .provider.pid
	@sleep 1
	@echo "Starting SDC consumer + dashboard on http://localhost:8000"
	@trap 'kill `cat .provider.pid` 2>/dev/null; rm -f .provider.pid' EXIT; \
	  $(UV) run python consumer.py

## provider Run only the provider
provider: sync data
	$(UV) run python provider.py --data data/gaitband-sample.csv

## consumer Run only the consumer + dashboard
consumer: sync
	$(UV) run python consumer.py

## data     (Re)generate the synthetic gait CSV
data: data/gaitband-sample.csv

data/gaitband-sample.csv: data/generate_synthetic_gait.py
	$(UV) run python data/generate_synthetic_gait.py --output $@

## clean    Remove generated data, pid files, and the venv
clean:
	rm -f .provider.pid
	rm -f data/gaitband-sample.csv
	rm -rf .venv
