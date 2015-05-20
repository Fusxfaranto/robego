
import module_base;

extern (C) IRCModule m;

import std.stdio;

static this()
{
    writeln("testo module constructor");
    m.commands["testo"] = function void(Client c, in char[] n, in char[] t)
        {
            writeln("testo command");
            writeln(n);
            writeln(t);
            c.send_raw("PRIVMSG #fusxbottest :<" ~ n ~ "> " ~ t/* ~ " poop"*/);
            c.delayed_callback({writeln("lazy");});
            c.delayed_callback({c.send_raw("PRIVMSG #fusxbottest :lazy");});
        };
    m.commands["reload"] = function void(Client c, in char[] n, in char[] t)
        {
            writeln("reload command");
            c.send_raw("PRIVMSG #fusxbottest :reload queued");
            c.delayed_reload();
        };
    m.commands["quit"] = function void(Client c, in char[] n, in char[] t)
        {
            c.send_raw("QUIT :quitting from command");
            c.delayed_quit();
        };
    m.listeners["PRIVMSG"] = function void(Client c, in char[] t)
        {
            writeln("testo listener");
        };
}

static ~this()
{
    writeln("testo module destructor");
}
