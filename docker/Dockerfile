FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        emacs-nox \
        texlive-xetex \
        texlive-latex-extra \
        texlive-fonts-recommended \
        texlive-fonts-extra \
        lmodern \
        fonts-dejavu \
        python3 \
        python3-pip \
        python3-venv \
        nodejs \
        npm \
        make \
        git \
        curl \
        ca-certificates \
        plantuml \
        graphviz \
        psmisc \
    && rm -rf /var/lib/apt/lists/*

# decktape --- reveal.js -> PDF exporter (bundles Chromium via puppeteer).
RUN npm install -g decktape@3.14.0 \
    && rm -rf /root/.npm

# Pre-install Emacs packages non-interactively so build.el is offline-friendly.
RUN mkdir -p /root/.emacs.d && \
    emacs --batch --eval "(progn \
      (require 'package) \
      (setq package-user-dir \"/opt/elpa\") \
      (add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t) \
      (package-initialize) \
      (package-refresh-contents) \
      (dolist (p '(htmlize ox-reveal simple-httpd)) \
        (unless (package-installed-p p) (package-install p))))"

# Make the pre-installed packages visible to any user via a site-start snippet.
RUN mkdir -p /etc/emacs/site-start.d && \
    printf '%s\n' \
      "(require 'package)" \
      "(add-to-list 'package-directory-list \"/opt/elpa\")" \
      "(setq package-user-dir \"/opt/elpa\")" \
      "(package-initialize)" \
      > /etc/emacs/site-start.d/50-elpa.el

# uv --- fast Python package + venv manager for the SDC demo.
# Actual Python deps for the demo are installed by `uv sync` at first `make demo`
# and live in demo/.venv, keeping this image lean.
RUN curl -LsSf https://astral.sh/uv/install.sh | \
      env UV_INSTALL_DIR=/usr/local/bin sh

WORKDIR /work

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
