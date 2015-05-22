// all dll stuff should only be touched in this file

import module_base;
import util;
import core.sys.posix.dlfcn;
import std.conv : to;
import io = std.stdio : writeln/*, writefln*/, write, stdout;
import std.file : dirEntries, SpanMode;
import std.string : toStringz;
import std.process : spawnProcess, wait;

class DLException : Exception
{
    public:
        this(string msg) {super(msg);}
}

void check_dlerror(in string s)
{
    if (char* e = dlerror())
    {
        throw new DLException(s ~ " - " ~ to!string(e));
    }
}

void*[] dlopen_ptrs = [];

void unload_dynamics(ref command_t[string] commands, ref listener_t[][string] listeners)
{
    debug writeln("unload_dynamics");
    commands = command_t[string].init;
    listeners = listener_t[][string].init;
    foreach (p; dlopen_ptrs)
    {
        debug writeln(p);
        dlclose(p);
    }
    dlopen_ptrs = [];
}

void reload_dynamics(ref command_t[string] commands, ref listener_t[][string] listeners)
{
    auto compilation_pid = spawnProcess(["make", "dynamic"]);
    if (wait(compilation_pid) != 0)
    {
        debug writeln("compilation failed, not reloading");
        debug assert(0);
        return;
    }

    unload_dynamics(commands, listeners);

    foreach (string so_name; dirEntries("./modules/", "*.so", SpanMode.shallow))
    {
        debug writeln("loading " ~ so_name);

        void* p = dlopen(so_name.toStringz(), RTLD_LAZY);
        check_dlerror("loading " ~ so_name);

        auto m = cast(IRCModule*)(dlsym(p, "m"));
        check_dlerror("importing from " ~ so_name);
        debug writeln(*m);

        aa_merge_inplace!(command_t, string)(commands, (*m).commands,
                                             function command_t(command_t a, command_t) {return a;});

        aa_merge_inplace!(listener_t[], listener_t, string)(listeners, (*m).listeners,
                                                            function listener_t[](listener_t[] a, listener_t b)
                                                            {return a ~ b;}, []);

        dlopen_ptrs ~= p;
    }
    commands.rehash();
    listeners.rehash();
}
