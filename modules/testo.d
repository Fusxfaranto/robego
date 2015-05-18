
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
            c.push_lazy_queue({c.send_raw("PRIVMSG #fusxbottest :lazy");});
        };
    m.commands["reload"] = function void(Client c, in char[] n, in char[] t)
        {
            writeln("reload command");
            c.push_lazy_queue({c.reload();});
            c.send_raw("PRIVMSG #fusxbottest :reload queued");
        };
    m.commands["quit"] = function void(Client c, in char[] n, in char[] t)
        {
            c.send_raw("QUIT :quitting from command");
            c.will_quit = true;
            //c.push_lazy_queue({c.push_lazy_queue({});});
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
