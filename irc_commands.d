// all dll stuff should only be touched in this file

import module_base;
import util;
import core.sys.posix.dlfcn;
import std.conv : to;
import io = std.stdio : writeln/*, writefln*/, write, stdout;
import std.file : dirEntries, SpanMode, timeLastModified, SysTime;
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

void unload_dynamics(ref Command*[string] commands, ref Listener*[][string] listeners)
{
    debug writeln("unload_dynamics");
    commands = typeof(commands).init;
    listeners = typeof(listeners).init;
    foreach (p; dlopen_ptrs)
    {
        debug writeln(p);
        dlclose(p);
    }
    dlopen_ptrs = [];
}

void reload_dynamics(ref Command*[string] commands, ref Listener*[][string] listeners)
{
    foreach (string src_name; dirEntries("./modules/", "*.d", SpanMode.shallow))
    {
        if (src_name.timeLastModified() >= src_name[0..$-2].timeLastModified(SysTime.min))
        {
            debug writeln("compiling " ~ src_name);
            auto compilation_pid = spawnProcess(["dmd", src_name, "-debug=1", "-O", "-inline",
                                                 "-fPIC", "-shared", "-defaultlib=libphobos2.so",
                                                 "-of" ~ src_name[0..$-1] ~ "so"]);
            if (wait(compilation_pid) != 0)
            {
                debug writeln("compilation failed, not reloading");
                debug assert(0);
                return;
            }
        }
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

        aa_merge_inplace!(Command*, string)(commands, m.commands, (Command* a, Command*) => a);

        aa_merge_inplace!(Listener*[], Listener*, string)(listeners, m.listeners,
                                                          (Listener*[] a, Listener* b) => a ~ b, []);

        dlopen_ptrs ~= p;
    }
    commands.rehash();
    listeners.rehash();
}
