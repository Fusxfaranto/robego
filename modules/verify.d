// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.stdio;
import std.uni : toLower;
import std.format : format;
import std.array : split;
import std.algorithm : map;

static this()
{
    m.commands["resync"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.users = typeof(c.users).init;
            c.channels = typeof(c.channels).init;
            c.send_raw("WHOIS ", c.nick); // to get a list of channels we're in
            c.temporary_listeners ~= TemporaryListener(
                delegate bool(in char[] source, in char[] command, in char[][] args, in char[] message)
                {
                    if (command == "319" // WHOIS channels reply
                        && args[0] == c.nick
                        && args[0] == args[1])
                    {
                        foreach (chan_name; message.split(' '))
                        {
                            c.send_raw("NAMES ", chan_name);
                        }
                        return true;
                    }
                    return false;
                });
        }, 3, channel_auth_t.NONE, 240);

    static Channel[] channels_with_user(Channel[string] channels, string lowered_nick)
    {
        Channel[] o;
        foreach (channel; channels.byValue())
        {
            if (lowered_nick in channel.users)
                o ~= channel;
        }
        return o;
    }

    m.commands["userstate"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            if (message.length)
            {
                string lowered_nick = message.toLower().idup;
                if (auto u = lowered_nick in c.users)
                {
                    c.send_privmsg(channel, format("%s", *u));
                    c.send_privmsg(channel,
                                   channels_with_user(c.channels, lowered_nick)
                                   .map!(a => a.cased_name)
                                   .join(", "));
                }
            }
            else
            {
                if (format("%s", c.channels).length < 450 &&
                    format("%s", c.users).length < 450)
                {
                    c.send_privmsg(channel, format("%s", c.users));
                    c.send_privmsg(channel, format("%s", c.channels));
                }
                writeln(c.users);
                writeln(c.channels);
            }
        }, 3, channel_auth_t.NONE, 240);

/*    m.commands["verify"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_privmsg("NickServ", "STATUS ", message);
            string nick = message.toLower().idup;
            c.temporary_listeners ~= TemporaryListener(
                delegate bool(in char[] source, in char[] command, in char[][] args, in char[] message)
                {
                    if (command == "NOTICE" && source.get_nick() == "NickServ")
                    {
                        auto s = message.splitN!2(' ');
                        debug writeln(s);
                        if (s[0] == "STATUS" && s[1].toLower() == nick)
                        {
                            if (auto u = nick in c.users)
                                u.ns_status = to!byte(s[2]);
                            return true;
                        }
                    }
                    return false;
                });
        });*/

    static void register_user(bool has_symbol = false)(Client c, string nick_in, string chan_name)
    {
        static if (has_symbol)
        {
            string nick;
            channel_auth_t* auth_level_p = nick_in[0] in auth_chars;
            channel_auth_t auth_level;
            if (auth_level_p)
            {
                nick = nick_in[1..$];
                auth_level = *auth_level_p;
            }
            else
            {
                nick = nick_in;
                auth_level = channel_auth_t.NONE;
            }
        }
        else
        {
            alias nick = nick_in;
        }

        const(char)[] lowered_nick = nick.toLower();
        GlobalUser* global = lowered_nick in c.users;
        if (!global)
            global = &(c.users[lowered_nick] = GlobalUser(nick));

        const(char)[] lowered_chan_name = chan_name.toLower();
        Channel* chan = lowered_chan_name in c.channels;
        if (!chan)
            chan = &(c.channels[lowered_chan_name] = Channel(chan_name));
        //assert(!(lowered_nick in chan.users));
        static if (has_symbol) chan.users[lowered_nick] = LocalUser(global, auth_level);
        else chan.users[lowered_nick] = LocalUser(global);
    }

    m.listeners["JOIN"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            // might have to use args.length == 1 ? args[0].idup : message.idup
            // but im not sure if that happens with joins
            register_user(c, source.get_nick().idup, message.idup);
            //writeln(c.users);
            //writeln(c.channels);
        });

    m.listeners["353"] = new Listener( // NAMES reply
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            foreach (nick; message.split())
            {
                register_user!true(c, nick.idup, args[2].idup);
            }
            //writeln(c.users);
            //writeln(c.channels);
        });

    m.listeners["KICK"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            m.listeners["PART"].f(c, args[1], [], args[0]);
        });

    m.listeners["PART"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            const(char)[] nick = source.get_nick();
            string lowered_chan_name = args.length == 1 ? args[0].toLower().idup : message.toLower().idup;
            assert(lowered_chan_name in c.channels,
                   format("%s", c.users) ~ "\n" ~ format("%s", c.channels));
            if (nick == c.nick)
            {
                c.channels.remove(lowered_chan_name);
                return;
            }

            string lowered_nick = nick.toLower().idup;
            assert(lowered_nick in c.channels[lowered_chan_name].users,
                   format("%s", c.users) ~ "\n" ~ format("%s", c.channels));
            c.channels[lowered_chan_name].users.remove(lowered_nick);
            c.users[lowered_nick].ns_status = -1;
        });

    m.listeners["QUIT"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            string lowered_nick = source.get_nick().toLower().idup;
            foreach (channel; c.channels)
            {
                channel.users.remove(lowered_nick);
            }

            assert(lowered_nick in c.users, format("%s", c.users) ~ "\n" ~ format("%s", c.channels));
            c.users.remove(lowered_nick);
        });

    m.listeners["NICK"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            string lowered_old_nick = source.get_nick().toLower().idup;
            string new_nick = message.idup;
            const(char)[] lowered_new_nick = new_nick.toLower();
            assert(lowered_old_nick in c.users, format("%s", c.users) ~ "\n" ~ format("%s", c.channels));

            if (lowered_old_nick == lowered_new_nick)
            {
                c.users[lowered_new_nick].cased_name = new_nick;
                return;
            }

            c.users[lowered_new_nick] = GlobalUser(message.idup, -1, c.users[lowered_old_nick].auth_level);
            c.users.remove(lowered_old_nick);

            foreach (channel; c.channels)
            {
                if (auto user_p = lowered_old_nick in channel.users)
                {
                    channel.users[lowered_new_nick] =
                        LocalUser(&c.users[lowered_new_nick], user_p.channel_auth_level);
                    channel.users.remove(lowered_old_nick);
                }
            }
        });
}
