// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

//import std.stdio;
import core.sys.linux.dlfcn;
import std.file : write, remove;
import std.string : replace;
import std.conv : to;
import std.uuid: randomUUID;

import irc_commands;

static this()
{
    m.commands["exec"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            string so_name = "module_files/eval/" ~ randomUUID().toString() ~ ".so";

            write("module_files/eval/temp.d",
                  "import module_base; import std.stdio; import std.variant : Variant;"
                  "import std.format : format;"
                  "extern (C) void f(in char[] message, in char[] channel, in char[] source, Client c) "
                  "{"
                  // "Client c = *(cast(Client*)0x" ~ to!string(&c) ~ ");"
                  ~ message ~
                  "}");
            //remove("module_files/eval/temp.o");
            //remove("module_files/eval/temp.so");

            auto compilation_pid = spawnProcess(["dmd", "module_files/eval/temp.d", "-g", "-debug=1", "-O",
                                                 "-inline", "-fPIC", "-shared", "-defaultlib=libphobos2.so",
                                                 "-of" ~ so_name]);
            if (wait(compilation_pid) != 0)
            {
                c.send_privmsg(channel, "error compiling");
                return;
            }

            void* p = dlopen(so_name.toStringz(), RTLD_LAZY);
            check_dlerror("loading temp eval file");

            // for some godforsaken reason the arguments get interpreted backwards
            auto f = cast(void function(Client c, in char[], in char[], in char[]))(dlsym(p, "f"));
            check_dlerror("importing eval function");

            f(c, source, channel, message);
            c.send_privmsg(channel, "done evaling");
            //dlclose(p);

            //writeln(source);
            //writeln(channel);
            //writeln(message);
        }, 3, UserChannelFlag.NONE, 255);

    m.commands["eval"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            m.commands["exec"].f(c, source, channel,
                                 "c.send_privmsg(channel,format(\"%s\"," ~ message ~ "));");
        }, 3, UserChannelFlag.NONE, 255);
}
