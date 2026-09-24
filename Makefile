# Vernetzte Systeme in der Medizin --- top-level Makefile.
#
# Runs on the host by default.  Set DOCKER_RUN=1 to run targets inside the
# pre-built container image.
#
# Usage:
#   make image      - build the Docker image
#   make html       - build reveal.js slides + HTML docs
#   make pdf        - export reveal.js talks to PDF via decktape
#   make glossar    - build the German glossary handout PDF (article)
#   make all        - html + glossar
#   make serve      - serve docs/public/ on :8080
#   make demo       - run the SDC provider + consumer + dashboard
#   make data       - regenerate synthetic gait CSV
#   make shell      - drop into the build container (DOCKER_RUN=1 implied)
#   make clean      - wipe docs/public/ and demo state
#
#   DOCKER_RUN=1 make html   - same, but inside the container

IMAGE      ?= ghcr.io/fabianfranzelin/vsm-build:latest
WORKDIR    := $(shell pwd)

# LOCAL is the default; set DOCKER=1 to run targets inside the container.
ifdef DOCKER_RUN
  DOCKER := docker run --rm -it \
              -v $(WORKDIR):/work \
              -w /work \
              -p 8080:8080 \
              -p 8000:8000 \
              -e HOME=/tmp \
              $(IMAGE)
else
  DOCKER :=
endif

.PHONY: image vendor clean-vendor diagrams html pdf glossar all serve demo data shell clean

image:
	docker build -t $(IMAGE) -f docker/Dockerfile .

# Mirror reveal.js, the pointer plugin, and Google Fonts into
# docs/content/assets/vendor/ so the built site works fully offline.
# Runs on the host (needs curl + tar + internet on first invocation).
vendor:
	./scripts/fetch-vendor.sh

clean-vendor:
	rm -rf docs/content/assets/vendor

DIAGRAM_HOL_SOL_SRC := docs/content/talks/images/en-digital-twin-vehicle-hol-sol.drawio
DIAGRAM_MW_SRC := docs/content/talks/images/en-safe-engineering-middleware.drawio
DIAGRAM_SVGS := \
	docs/content/talks/images/en-digital-twin-vehicle-hol-sol-background.svg \
	docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-1.svg \
	docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-2.svg \
	docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-3.svg \
	docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-4.svg \
	docs/content/talks/images/en-digital-twin-vehicle-uq.svg \
	docs/content/talks/images/en-safe-engineering-middleware-background.svg \
	docs/content/talks/images/en-safe-engineering-middleware-step-1.svg

diagrams: $(DIAGRAM_SVGS)

# Digital Twin ################################################################

docs/content/talks/images/en-digital-twin-vehicle-hol-sol-background.svg: $(DIAGRAM_HOL_SOL_SRC)
	$(DOCKER) drawio --export --format svg --size page --layers 0 --output $@ $<

docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-1.svg: $(DIAGRAM_HOL_SOL_SRC)
	$(DOCKER) drawio --export --format svg --size page --layers 0,1 --output $@ $<

docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-2.svg: $(DIAGRAM_HOL_SOL_SRC)
	$(DOCKER) drawio --export --format svg --size page --layers 0,1,2 --output $@ $<

docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-3.svg: $(DIAGRAM_HOL_SOL_SRC)
	$(DOCKER) drawio --export --format svg --size page --layers 0,1,2,3 --output $@ $<

docs/content/talks/images/en-digital-twin-vehicle-hol-sol-step-4.svg: $(DIAGRAM_HOL_SOL_SRC)
	$(DOCKER) drawio --export --format svg --size page --layers 0,1,2,3,4 --output $@ $<

docs/content/talks/images/en-digital-twin-vehicle-uq.svg: docs/content/talks/images/en-digital-twin-vehicle-uq.drawio
	$(DOCKER) drawio --export --format svg --size page --output $@ $<

# Safe Engineering ############################################################

docs/content/talks/images/en-safe-engineering-middleware-background.svg: $(DIAGRAM_MW_SRC) docs/content/talks/images/en-safe-engineering-middleware.drawio
	$(DOCKER) drawio --export --format svg --size page --layers 0 --output $@ $<

docs/content/talks/images/en-safe-engineering-middleware-step-1.svg: $(DIAGRAM_MW_SRC) docs/content/talks/images/en-safe-engineering-middleware.drawio
	$(DOCKER) drawio --export --format svg --size page --layers 0,1 --output $@ $<

# Others ######################################################################

html: vendor diagrams
	$(DOCKER) emacs -Q --script build.el

# PDF exports of the reveal.js talks (via decktape).
# Output: docs/public/talks/<slug>.pdf
TALK_SLUGS := \
	de-telematikinfrastruktur \
	en-digital-twins \
	en-safe-engineering \
	en-service-oriented-communication
PDF_PORT ?= 8090

pdf: html
	$(DOCKER) env PDF_PORT=$(PDF_PORT) ./scripts/export-pdfs.sh $(TALK_SLUGS)

# Glossary handout (German) --- rendered as a plain LaTeX article (not Beamer)
# via Emacs's `org-latex-export-to-pdf`.  Output lands in
# docs/public/talks/de-glossar.pdf.
GLOSSAR_SRC := docs/content/talks/de-glossar.org
GLOSSAR_OUT := docs/public/talks/de-glossar.pdf

glossar:
	@mkdir -p $(dir $(GLOSSAR_OUT))
	$(DOCKER) emacs -Q --batch \
	  -l org \
	  --eval "(setq org-latex-pdf-process '(\"pdflatex -interaction=nonstopmode -output-directory=%o %f\" \"pdflatex -interaction=nonstopmode -output-directory=%o %f\"))" \
	  --visit=$(GLOSSAR_SRC) \
	  -f org-latex-export-to-pdf
	mv docs/content/talks/de-glossar.pdf $(GLOSSAR_OUT)

all: html glossar

serve:
	$(DOCKER) emacs -Q --script serve.el

demo:
	$(MAKE) -C demo demo

data:
	$(MAKE) -C demo data

shell:
	docker run --rm -it \
	  -v $(WORKDIR):/work -w /work \
	  -p 8080:8080 -p 8000:8000 \
	  -e HOME=/tmp $(IMAGE) bash

clean:
	rm -rf docs/public
	$(MAKE) -C demo clean
