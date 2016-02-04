
MODULES := $(wildcard modules/*.d)
MODULE_SOS := $(subst modules,modules_lib,$(MODULES:.d=.so))

all: main $(MODULE_SOS)

main: main.d util.d irc.d irc_commands.d delayed_action.d user.d module_base.d
	dmd $^ -g -debug=1 -O -inline -L-ldl -defaultlib=libphobos2.so -ofmain

modules_lib/%.so: modules/%.d main
	dmd $< -g -debug=1 -O -inline -fPIC -shared -defaultlib=libphobos2.so -of$@

run:
	./main

clean:
	$(RM) main

#-O -release -inline -boundscheck=off
