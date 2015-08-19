import module_base;
import util;

import core.sys.posix.dlfcn;
import std.conv : to;
import io = std.stdio : writeln/*, writefln*/, write, stdout;
import std.file : copy, mkdir, rmdirRecurse, dirEntries, SpanMode, timeLastModified, SysTime;
import std.string : toStringz;
import std.process : spawnProcess, wait;
import std.uuid: randomUUID;

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

struct SO
{
    void* p;
    IRCModule* m;
    bool active = true;
}

//private void*[] dlopen_ptrs = [];
//private string[] loaded_sos = [];

private SO[string] loaded_sos;

private string[] previous_uuids = [];

void clear_imports(ref Command*[string] commands, ref Listener*[][string] listeners)
{
    debug writeln("clear_imports");
    commands = typeof(commands).init;
    listeners = typeof(listeners).init;
}

void import_from_loaded_sos(ref Variant[string] module_data, ref Command*[string] commands,
                            ref Listener*[][string] listeners, bool first_time)
{
    clear_imports(commands, listeners);

    foreach (SO so; loaded_sos)
    {
        if (so.active)
        {
            aa_merge_inplace!(Command*, string)(commands, so.m.commands, (Command* a, Command*) => a);

            aa_merge_inplace!(Listener*[], Listener*, string)(listeners, so.m.listeners,
                                                              (Listener*[] a, Listener* b) => a ~ b, []);
            if (so.m.initialize)
                so.m.initialize(module_data, first_time);
            else
                debug writeln("no init function");

            debug writeln(module_data);
        }
    }
    commands.rehash();
    listeners.rehash();
}

void load_so(string so_name, ref Command*[string] commands, ref Listener*[][string] listeners)
{
    debug writeln("loading " ~ so_name);

    void* p = dlopen(so_name.toStringz(), RTLD_LAZY);
    check_dlerror("loading " ~ so_name);

    auto m = cast(IRCModule*)(dlsym(p, "m"));
    check_dlerror("importing from " ~ so_name);
    debug writeln(*m);

    assert(so_name !in loaded_sos);
    foreach (so; loaded_sos) assert(p != so.p, so_name);
    loaded_sos[so_name] = SO(p, m);
}

void unload_dynamics(ref Command*[string] commands, ref Listener*[][string] listeners)
{
    foreach (SO so; loaded_sos)
    {
        debug writeln("unload_dynamics ", so.p);
        dlclose(so.p);
    }
    debug loaded_sos = null;
    debug writeln("unload_dynamics done");

    //rmdirRecurse("./modules_lib_temp/");
}

void reload_dynamics(ref Variant[string] module_data,
                     ref Command*[string] commands, ref Listener*[][string] listeners)
{
    bool first_time = loaded_sos.length == 0;
    if (first_time)
    {
        rmdirRecurse("./modules_lib_temp/");
        mkdir("./modules_lib_temp/");
    }

    string uuid = randomUUID().toString();

    foreach (string src_name; dirEntries("./modules/", "*.d", SpanMode.shallow))
    {
        string so_name = "./modules_lib/" ~ src_name[10..$-1] ~ "so";
        bool copy_and_load = first_time;
        if (src_name.timeLastModified() >= so_name.timeLastModified(SysTime.min))
        {
            debug writeln("compiling " ~ src_name);
            auto compilation_pid = spawnProcess(["dmd", src_name, "-g", "-debug=1", "-O", "-inline",
                                                 "-fPIC", "-shared", "-defaultlib=libphobos2.so",
                                                 "-of" ~ so_name]);
            if (wait(compilation_pid) != 0)
            {
                debug writeln("compilation failed, not recompiling this module");
                debug assert(0);
                //return;
            }
            copy_and_load = true;
        }

        if (copy_and_load)
        {
            string copy_so_name = "./modules_lib_temp/" ~ src_name[10..$-2] ~ uuid ~ ".so";
            copy(so_name, copy_so_name);
            load_so(copy_so_name, commands, listeners);

            foreach (pu; previous_uuids)
            {
                string previous_so_name = "./modules_lib_temp/" ~ src_name[10..$-2] ~ pu ~ ".so";
                if (SO* p = previous_so_name in loaded_sos)
                {
                    p.active = false;
                }
            }
        }
    }

    import_from_loaded_sos(module_data, commands, listeners, first_time);

    previous_uuids ~= uuid;

}
