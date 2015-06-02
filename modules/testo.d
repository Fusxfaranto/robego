// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.stdio;

static this()
{
    writeln("testo module constructor");
    m.commands["testo"] = function void(Client c, in char[] source, in char[] message)
        {
            writeln("testo command");
            writeln(source);
            writeln(message);
            c.send_raw("PRIVMSG #fusxbottest :<" ~ source ~ "> " ~ message/* ~ " poop"*/);
            c.delayed_actions.insert(new DelayedCallback({writeln("lazy");}));
            c.delayed_actions.insert(new DelayedCallback({c.send_raw("PRIVMSG #fusxbottest :lazy");}, 10000));
        };
    m.commands["reload"] = function void(Client c, in char[] source, in char[] message)
        {
            writeln("reload command");
            c.send_raw("PRIVMSG #fusxbottest :reload queued");
            c.delayed_actions.insert(new DelayedReload());
        };
    m.commands["quit"] = function void(Client c, in char[] source, in char[] message)
        {
            c.send_raw("QUIT :quitting from command");
            c.delayed_actions.insert(new DelayedQuit());
        };
    m.commands["null"] = null;
    m.listeners["PRIVMSG"] = function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            writeln("testo privmsg listener");
        };
    m.listeners["JOIN"] = function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            writeln("testo join listener");
        };
}

static ~this()
{
    writeln("testo module destructor");
}
