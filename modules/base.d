// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

debug import std.stdio;
import std.uni : toLower;

static this()
{
    m.commands["reload"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            debug writeln("reload command");
            c.send_privmsg("#fusxbottest", "reload queued");
            c.delayed_actions.insert(new DelayedReload());
            c.delayed_actions.insert(new DelayedCallback({c.send_raw("PRIVMSG #fusxbottest :reloaded");}));
        }, 3, UserChannelFlag.NONE, 250);

    m.commands["quit"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_raw("QUIT :quitting from command");
            c.delayed_actions.insert(new DelayedQuit());
        }, 3, UserChannelFlag.NONE, 240);

    m.commands["raw"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_raw(message);
        }, 3, UserChannelFlag.NONE, 250);

    m.commands["join"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_join(message);
        }, 3, UserChannelFlag.NONE, 240);

    m.commands["part"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_part(message);
        }, 3, UserChannelFlag.NONE, 240);

    m.listeners["PING"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            c.send_raw("PONG :", message);
            debug writeln("sent pong");
            if (!c.ready)
            {
                c.ready = true;
                c.send_raw("CAP REQ multi-prefix"); // TODO: check for CAP ACK response
                c.send_join(c.config.initial_channels);
            }
        });
}
