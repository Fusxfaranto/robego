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
                c.send_join(c.initial_channels);
            }
        });

    m.listeners["PRIVMSG"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            if (message.length >= 2 && message[0] == COMMAND_CHAR)
            {
                const(char)[][2] msg = split1(message[1..$], ' ');
                if (Command** p = msg[0] in c.commands)
                {
                    Command* cmd = *p;
                    const(char)[] nick = source.get_nick();
                    string lowered_nick = nick.toLower().idup;
                    bool in_channel = args[0].is_channel();

                    Channel* channel;
                    LocalUser* user;
                    GlobalUser* guser;
                    if (in_channel)
                    {
                        channel = args[0].toLower() in c.channels;
                        assert(channel);
                        user = lowered_nick in channel.users;
                        assert(user);
                        guser = user.global_reference;
                        assert(guser == (lowered_nick in c.users));
                    }
                    else
                    {
                        guser = lowered_nick in c.users;
                        assert(guser); // TODO: fix this, will crash if no channels are shared
                    }

                    if (in_channel && user.user_channel_flags < cmd.min_channel_auth_level)
                        c.send_privmsg(args[0], "Error - your channel auth level "
                                       "is too low to use this command.");
                    else if (guser.auth_level < cmd.min_auth_level)
                        c.send_privmsg(args[0], "Error - you are not allowed to use this command.");
                    else if (guser.ns_status < cmd.min_ns_status)
                    {
                        if (guser.ns_status == -1)
                        {
                            alias source_ = source;
                            alias args_ = args;
                            alias message_ = message;
                            c.send_privmsg("NickServ", "STATUS ", nick);
                            assert(!c.temporary_listener.action);
                            c.temporary_listener = TemporaryListener(
                                delegate TLOption(in char[] source, in char[] command,
                                              in char[][] args, in char[] message)
                                {
                                    if (command == "NOTICE" && source.get_nick() == "NickServ")
                                    {
                                        auto s = message.splitN!2(' ');
                                        if (s[0] == "STATUS" && s[1].toLower() == lowered_nick)
                                        {
                                            auto u = lowered_nick in c.users;
                                            assert(u == guser);
                                            u.ns_status = to!byte(s[2]);
                                            assert(guser.ns_status != -1);
                                            m.listeners["PRIVMSG"].f(c, source_, args_, message_);
                                            return TLOption.DONE;
                                        }
                                    }
                                    return TLOption.QUEUE;
                                });
                        }
                        else
                            c.send_privmsg(args[0], "Error - you must be identified to use this command.");
                    }
                    else
                    {
                        if (in_channel)
                            cmd.f(c, source, args[0], msg[1]);
                        else
                            cmd.f(c, source, nick, msg[1]);
                    }
                }
            }
        });
}
