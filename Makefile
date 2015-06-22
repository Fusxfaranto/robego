all: main.d
	dmd main.d util.d irc.d irc_commands.d delayed_action.d user.d module_base.d -debug=1 -g -O -inline -L-ldl -defaultlib=libphobos2.so -L-rpath=\$ORIGIN/modules -ofmain

run:
	./main

dynamic:
	dmd modules/testo.d -debug=1 -O -inline -fPIC -shared -defaultlib=libphobos2.so -ofmodules/testo.so
	dmd modules/base.d -debug=1 -O -inline -fPIC -shared -defaultlib=libphobos2.so -ofmodules/base.so
	dmd modules/verify.d -debug=1 -O -inline -fPIC -shared -defaultlib=libphobos2.so -ofmodules/verify.so
	dmd modules/eval.d -debug=1 -O -inline -fPIC -shared -defaultlib=libphobos2.so -ofmodules/eval.so

clean:
	$(RM) main

#-O -release -inline -boundscheck=off
