// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.stdio;

static this()
{
    writeln("testo module constructor");

    m.commands["testo"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            writeln("testo command");
            writeln(source);
            writeln(channel);
            writeln(message);
            c.send_raw("PRIVMSG #fusxbottest :", channel, ": <", source, "> ", message/*, " poop"*/);
            c.delayed_actions.insert(new DelayedCallback({writeln("lazy");}));
            c.delayed_actions.insert(new DelayedCallback({c.send_raw("PRIVMSG #fusxbottest :lazy");}, 4000));
        }, -1, channel_auth_t.NONE, 0);

    m.commands["adminme"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.users["fusxfaranto"].auth_level = 255;
        }, -1, channel_auth_t.NONE, 0);

    // m.listeners["PRIVMSG"] = new Listener(
    //     function void(Client c, in char[] source, in char[][] args, in char[] message)
    //     {
    //         writeln("testo privmsg listener");
    //     });

    // m.listeners["JOIN"] = new Listener(
    //     function void(Client c, in char[] source, in char[][] args, in char[] message)
    //     {
    //         writeln("testo join listener");
    //     });
}

static ~this()
{
    writeln("testo module destructor");
}
