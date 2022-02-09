BUILD_DIR := $(CURDIR)/_build
CONCUERROR := $(BUILD_DIR)/Concuerror/bin/concuerror
CONCUERROR_RUN := $(CONCUERROR) \
	--treat_as_normal shutdown --treat_as_normal normal \
	-x code -x code_server -x error_handler \
	-pa $(BUILD_DIR)/concuerror+test/lib/snabbkaffe/ebin

GEN_TESTS=$(patsubst doc/src/%.md, test/%_example.erl, $(wildcard doc/src/*.md))

.PHONY: all
all: $(GEN_TESTS)
	rebar3 do dialyzer, eunit, ct --sname snk_main, xref

.PHONY: doc
doc:
	rebar3 as dev ex_doc

.PHONY: clean
clean:
	rm -rf _build/
	rm test/*_example.erl

test/%_example.erl: doc/src/%.md doc/src/extract_tests
	./doc/src/extract_tests $< > $@

concuerror = \
	@echo "\n=========================================\nRunning $(1)\n=========================================\n"; \
	$(CONCUERROR_RUN) -f $(BUILD_DIR)/concuerror+test/lib/snabbkaffe/test/concuerror_tests.beam -t $(1) || \
	{ cat concuerror_report.txt; exit 1; }

.PHONY: concuerror_test
concuerror_test: $(CONCUERROR)
	rebar3 as concuerror eunit -m concuerror_tests
	$(call concuerror,race_test)
	$(call concuerror,block_until_multiple_events_test)
	$(call concuerror,block_until_timeout_test)
	$(call concuerror,causality_test)
	$(call concuerror,fail_test)
	$(call concuerror,force_order_test)
	$(call concuerror,force_order_multiple_predicates_test)
	$(call concuerror,force_order_parametrized_test)
	$(call concuerror,force_order_multiple_events_test)

$(CONCUERROR):
	mkdir -p _build/
	cd _build && git clone https://github.com/parapluu/Concuerror.git
	$(MAKE) -C _build/Concuerror/
