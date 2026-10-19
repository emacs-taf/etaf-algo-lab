.DEFAULT_GOAL := check
.NOTPARALLEL:
EMACS ?= emacs
EMACSCLIENT ?= emacsclient

# Providers live beside the application (standalone) or two levels up (workspace).
# Providers are siblings in the workspace and in a standalone clone;
# override PROVIDER_ROOT to pin another checkout.
PROVIDER_ROOT ?= ..

LOAD_PATH = -L . -L lisp -L tests -L $(PROVIDER_ROOT)/etaf -L $(PROVIDER_ROOT)/etaf-ui \
            -L $(PROVIDER_ROOT)/ebox -L $(PROVIDER_ROOT)/ecss -L $(PROVIDER_ROOT)/etaf/scripts

SOURCES = $(wildcard lisp/*.el) etaf-algo-lab.el
SOURCES += scripts/etaf-algo-lab-gui-scenarios.el benchmarks/performance-scenarios.el

.PHONY: all compile load test check structure-check setup-hooks acceptance api-check gui clean

all: check

compile:
	rm -f *.elc lisp/*.elc tests/*.elc scripts/*.elc benchmarks/*.elc
	$(EMACS) -Q --batch $(LOAD_PATH) \
		--eval '(setq load-prefer-newer t byte-compile-error-on-warn t)' \
		--eval '(require (quote cl-lib))' \
		--eval '(unless (cl-every (function byte-compile-file) (quote ($(foreach file,$(SOURCES),"$(file)")))) (kill-emacs 1))'

load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) \
		--eval '(require (quote etaf-algo-lab))' \
		--eval '(princ "etaf-algo-lab load OK\n")'

test: acceptance

check: structure-check compile acceptance api-check

structure-check:
	python3 scripts/check-repository.py

setup-hooks:
	git config --local core.hooksPath .githooks

acceptance:
	python3 scripts/run-acceptance.py --emacs "$(EMACS)"

api-check:
	$(EMACS) -Q --batch -L . $(LOAD_PATH) --eval '(setq load-prefer-newer t)' -l scripts/check-api.el

# Run the maintained GUI scenario in an existing owned server and print a fresh
# evidence directory; pass SERVER=<name> for a dedicated verification instance.
gui:
	$(EMACSCLIENT) $(if $(SERVER),--socket-name "$(SERVER)",) --eval '(progn (require (quote etaf-algo-lab)) (add-to-list (quote load-path) (expand-file-name "scripts" (file-name-directory (locate-library "etaf")))) (add-to-list (quote load-path) "$(CURDIR)/scripts") (load "$(CURDIR)/scripts/etaf-algo-lab-gui-scenarios.el" nil t) (let ((directory (make-temp-file "etaf-algo-lab-gui-" t))) (run-at-time 0.05 nil (function etaf-algo-lab-gui-run) directory) directory))'

clean:
	rm -f *.elc lisp/*.elc tests/*.elc scripts/*.elc benchmarks/*.elc
