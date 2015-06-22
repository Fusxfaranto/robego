// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.stdio;

static this()
{
    m.commands["reload"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            writeln("reload command");
            c.send_privmsg("#fusxbottest", "reload queued");
            c.delayed_actions.insert(new DelayedReload());
        });

    m.commands["quit"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_raw("QUIT :quitting from command");
            c.delayed_actions.insert(new DelayedQuit());
        });

    m.commands["raw"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_raw(message);
        });

    m.commands["join"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_join(message);
        });

    m.commands["part"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_part(message);
        });

    m.listeners["PING"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            c.send_raw("PONG :", message);
            debug writeln("sent pong");
            if (!c.ready)
            {
                c.ready = true;
                c.send_join(c.initial_channels);
            }
        });

    m.listeners["PRIVMSG"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            if (message.length >= 2 && message[0] == COMMAND_CHAR)
            {
                const(char)[][2] m = split1(message[1..$], ' ');
                if (Command** p = m[0] in c.commands)
                {
                    debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
                    if (args[0].is_channel())
                        (*p).f(c, source, args[0], m[1]);
                    else
                        (*p).f(c, source, source.get_nick(), m[1]);
                    debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
                }
            }
        });

    // TODO: eval function (via dynamic loading, maybe should be its own file)
}
