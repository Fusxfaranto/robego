// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.stdio;

static this()
{
    writeln("testo module constructor");
    m.commands["testo"] = Command(function void(Client c, in char[] source, in char[] message)
        {
            writeln("testo command");
            writeln(source);
            writeln(message);
            c.send_raw("PRIVMSG #fusxbottest :<" ~ source ~ "> " ~ message/* ~ " poop"*/);
            c.delayed_actions.insert(new DelayedCallback({writeln("lazy");}));
            c.delayed_actions.insert(new DelayedCallback({c.send_raw("PRIVMSG #fusxbottest :lazy");}, 4000));
        });
    m.commands["reload"] = Command(function void(Client c, in char[] source, in char[] message)
        {
            writeln("reload command");
            c.send_raw("PRIVMSG #fusxbottest :reload queued");
            c.delayed_actions.insert(new DelayedReload());
        });
    m.commands["quit"] = Command(function void(Client c, in char[] source, in char[] message)
        {
            c.send_raw("QUIT :quitting from command");
            c.delayed_actions.insert(new DelayedQuit());
        });
    m.listeners["PRIVMSG"] = Listener(function void(Client c, in char[] source,
                                                    in char[][] args, in char[] message)
        {
            writeln("testo privmsg listener");
        });
    m.listeners["JOIN"] = Listener(function void(Client c, in char[] source,
                                                 in char[][] args, in char[] message)
        {
            writeln("testo join listener");
        });
}

static ~this()
{
    writeln("testo module destructor");
}
