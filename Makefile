PROJECT  = vk_api_lp

REBAR    = $(shell which rebar 2>/dev/null || echo $(PWD)/rebar)
RELX     = ./relx
ERL      = erl
LIBS     = ERL_LIBS=apps:deps

DEBUG=true

.PHONY: deps

compile: deps
	@$(LIBS) $(REBAR) compile

deps:
	@$(REBAR) get-deps

clean:
	find apps -name "*.o" -delete
	find apps -name "*.so" -delete
	find apps -name "*.beam" -delete
	find deps -name "*.o" -delete
	find deps -name "*.so" -delete
	find deps -name "*.beam" -delete
	@$(REBAR) clean

release: compile
	@$(RELX) release tar

run: compile
	ERL_LIBS=deps:apps erl -config etc/develop.config -name vk_api_lp@127.0.0.1 -pa ebin -s vk_api_lp

run_rel: 
	CONFIG_PATH=etc/develop.config _rel/$(PROJECT)/bin/$(PROJECT) console

run_dev: compile
	$(LIBS) $(ERL) -config etc/develop.config -name vk_api_lp@127.0.0.1 -$(PROJECT) debug $(DEBUG) -s $(PROJECT)
plugins/: deps
	mkdir plugins
	(cd deps/rebar_vsn_plugin/ && ../../rebar compile && cp ebin/rebar_vsn_plugin.beam ../../plugins/)
	(cd deps/rebar_vsn_rel_plugin/ && ../../rebar compile && cp ebin/rebar_vsn_rel_plugin.beam ../../plugins/)

build-plt:
	@$(DIALYZER) --build_plt --output_plt $(PROJECT).plt --apps erts kernel stdlib compiler crypto

dialyze:
	@$(DIALYZER) --src src --plt $(PROJECT).plt -Werror_handling -Wrace_conditions -Wunmatched_returns
