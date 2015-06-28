// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

//import std.stdio;
import core.sys.posix.dlfcn;
import std.file : write, remove;
import std.string : replace;
import std.conv : to;

import irc_commands;

static this()
{
    m.commands["exec"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            write("module_files/eval/temp.d",
                  "import module_base; import std.stdio;"
                  "extern (C) void f(in char[] message, in char[] channel, in char[] source, Client c) "
                  "{"
                  // "Client c = *(cast(Client*)0x" ~ to!string(&c) ~ ");"
                  ~ message ~
                  "}");
            //remove("module_files/eval/temp.o");
            //remove("module_files/eval/temp.so");

            auto compilation_pid = spawnProcess("dmd module_files/eval/temp.d -O -fPIC -shared "
                                                "-defaultlib=libphobos2.so "
                                                "-ofmodule_files/eval/temp.so".split());
            if (wait(compilation_pid) != 0)
            {
                c.send_privmsg(channel, "error compiling");
                return;
            }

            void* p = dlopen("module_files/eval/temp.so".toStringz(), RTLD_LAZY);
            check_dlerror("loading temp eval file");

            // for some godforsaken reason the arguments get interpreted backwards
            auto f = cast(void function(Client c, in char[], in char[], in char[]))(dlsym(p, "f"));
            check_dlerror("importing eval function");

            f(c, source, channel, message);
            c.send_privmsg(channel, "done evaling");
            dlclose(p);

            writeln(source);
            writeln(channel);
            writeln(message);
        }, 3, channel_auth_t.NONE, 255);

    m.commands["eval"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            m.commands["exec"].f(c, source, channel,
                                 "import std.format : format;"
                                 "c.send_privmsg(channel,format(\"%s\"," ~ message ~ "));");
        }, 3, channel_auth_t.NONE, 255);
}
