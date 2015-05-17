// all dll stuff should only be touched in this file

import module_base;
import util;
import core.sys.posix.dlfcn;
import std.conv : to;
import io = std.stdio : writeln/*, writefln*/, write, stdout;
import std.file : dirEntries, SpanMode;
import std.string : toStringz;

class Dl_exception : Exception
{
    public:
        this(string msg) {super(msg);}
}

void check_dlerror(in string s)
{
    if (char* e = dlerror())
    {
        throw new Dl_exception(s ~ " - " ~ to!string(e));
    }
}

void*[] dlopen_ptrs = [];

void reload_dynamics(ref command_t[string] commands, ref listener_t[][string] listeners)
{
    commands = command_t[string].init;
    listeners = listener_t[][string].init;
    foreach (p; dlopen_ptrs)
    {
        writeln(p);
        stdout.flush;
        dlclose(p);
    }

    foreach (string so_name; dirEntries("./modules/", "*.so", SpanMode.shallow))
    {
        void* p = dlopen(so_name.toStringz(), RTLD_LAZY);
        check_dlerror("loading " ~ so_name);

        auto m = cast(IRCModule*)(dlsym(p, "m"));
        check_dlerror("importing from " ~ so_name);
        debug writeln(*m);

        aa_merge_inplace!(command_t, string)(commands, (*m).commands,
                                           function command_t(command_t a, command_t) {return a;});
        commands.rehash();

        aa_merge_inplace!(listener_t[], listener_t, string)(listeners, (*m).listeners,
                                                        function listener_t[](listener_t[] a, listener_t b)
                                                        {return a ~ b;}, []);
        listeners.rehash();

        dlopen_ptrs ~= p;
    }
}

//void* p;
/*
static this()
{
    // command[string] commands;
    // listener[][string] listeners;
    // reload_dynamics(commands, listeners);
    // writeln(commands);
    // writeln(listeners);

    // p = dlopen("./modules/testo.so", RTLD_LAZY);
    // check_dlerror("loading testo.so error");

    // // auto f = cast(void function())dlsym(p, "testo");
    // // check_dlerror("importing testo error");
    // // f();

    // auto m = *(cast(IRCModule*)(dlsym(p, "m")));
    // check_dlerror("importing commands error");
    // writeln(m);
}


static ~this()
{
    // foreach (p; dlopen_ptrs)
    // {
    //     writeln(p);
    //     stdout.flush;
    //     dlclose(p);
    // }
    debug writeln("irc_commands destructor");
    debug stdout.flush();
}
*/
