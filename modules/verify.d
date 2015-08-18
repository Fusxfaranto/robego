// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.stdio;
import std.uni : toLower;
import std.format : format;
import std.array : split;
import std.string : strip;
import std.algorithm : map;
import std.container : redBlackTree, RedBlackTree;

GlobalUser[string]* old_users;
Channel[string]* old_channels;

static this()
{
    m.initialize = function void(ref Variant[string] module_data)
        {
            module_data.register_module_data!old_users();
            module_data.register_module_data!old_channels();
        };

    m.commands["resync"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            *old_users = c.users.dup;
            *old_channels = c.channels.dup;
            c.users = c.users.init;
            c.channels = c.channels.init;

            debug writeln(&old_users);
            debug writeln(&old_channels);

            c.send_raw("WHOIS ", c.config.nick); // to get a list of channels we're in
            RedBlackTree!(string) waiting_on_channels = null;
            c.temporary_listener = TemporaryListener(
                delegate TLOption(in char[] source, in char[] command, in char[][] args, in char[] message)
                {
                    debug writeln(source, ' ', command, ' ', args, ' ', message);
                    debug if (waiting_on_channels) writeln(waiting_on_channels[]);
                    if (command == "319" // WHOIS channels reply
                        && args[0] == c.config.nick
                        && args[0] == args[1])
                    {
                        assert(waiting_on_channels is null);
                        waiting_on_channels = redBlackTree(message.strip().idup.split(' '));
                        foreach (chan_name; waiting_on_channels)
                        {
                            c.send_raw("NAMES ", chan_name);
                        }
                    }
                    else if (waiting_on_channels !is null)
                    {
                        if (command == "353" // NAMES reply
                            && args[2].toLower().idup in waiting_on_channels)
                        {
                            debug writeln(args[2].toLower());
                            return TLOption.RUN_THIS;
                        }
                        else if (command == "366" // end of NAMES
                                 && waiting_on_channels.removeKey(args[1].toLower().idup))
                        {
                            debug writeln(args[1].toLower());
                            if (waiting_on_channels.empty()) return TLOption.DONE;
                        }
                    }
                    return TLOption.QUEUE;
                });
        }, 3, UserChannelFlag.NONE, 240);

    m.commands["compareold"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            alias users_diff = aa_diff!(deep_compare!GlobalUser, GlobalUser[string]);
            alias channel_diff = aa_diff!(deep_compare!Channel, Channel[string]);
            c.send_privmsg(channel, "diff from old users: ",
                           format("%s", users_diff(c.users, *old_users)));
            c.send_privmsg(channel, "diff from new users: ",
                           format("%s", users_diff(*old_users, c.users)));
            c.send_privmsg(channel, "diff from old channels: ",
                           format("%s", channel_diff(c.channels, *old_channels).byKey()));
            c.send_privmsg(channel, "diff from new channels: ",
                           format("%s", channel_diff(*old_channels, c.channels).byKey()));
        }, 3, UserChannelFlag.NONE, 240);

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
        }, 3, UserChannelFlag.NONE, 240);

/*    m.commands["verify"] = new Command(
      function void(Client c, in char[] source, in char[] channel, in char[] message)
      {
      c.send_privmsg("NickServ", "STATUS ", message);
      string nick = message.toLower().idup;
      c.temporary_listener = TemporaryListener(
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

    static void register_user(bool has_symbols = false)(Client c, string nick_in, string chan_name)
    {
        static if (has_symbols)
        {
            // TODO: account for servers without namesx
            string nick = nick_in;
            UserChannelFlag* auth_level_p = nick[0] in auth_chars;
            UserChannelFlagSet auth_level = UserChannelFlag.NONE;
            while (auth_level_p)
            {
                nick = nick[1..$];
                auth_level |= *auth_level_p;
                auth_level_p = nick[0] in auth_chars;
            }
        }
        else
        {
            alias nick = nick_in;
        }

        const(char)[] lowered_nick = nick.toLower();
        GlobalUser* global = lowered_nick in c.users;

        const(char)[] lowered_chan_name = chan_name.toLower();
        Channel* chan = lowered_chan_name in c.channels;
        if (!chan)
            chan = &(c.channels[lowered_chan_name] = Channel(chan_name));

        if (global)
        {
            assert(global.ref_count >= 1);
            if (lowered_nick !in chan.users)
                global.ref_count += 1;
        }
        else
            global = &(c.users[lowered_nick] = GlobalUser(nick));

        //assert(!(lowered_nick in chan.users));
        static if (has_symbols) chan.users[lowered_nick] = LocalUser(global, auth_level);
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

            if (nick == c.config.nick)
            {
                c.channels.remove(lowered_chan_name);
                return;
            }

            string lowered_nick = nick.toLower().idup;
            assert(lowered_nick in c.channels[lowered_chan_name].users,
                   format("%s", c.users) ~ "\n" ~ format("%s", c.channels));
            c.channels[lowered_chan_name].users.remove(lowered_nick);

            GlobalUser* user = lowered_nick in c.users;
            assert(user.ref_count);
            user.ref_count -= 1;
            if (user.ref_count == 0)
                c.users.remove(lowered_nick);
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

            GlobalUser* user = lowered_old_nick in c.users;
            assert(user.ref_count);
            c.users[lowered_new_nick] = GlobalUser(message.idup, -1, user.auth_level, user.ref_count);
            c.users.remove(lowered_old_nick);

            foreach (channel; c.channels)
            {
                if (LocalUser* luser = lowered_old_nick in channel.users)
                {
                    channel.users[lowered_new_nick] =
                        LocalUser(&c.users[lowered_new_nick], luser.user_channel_flags);
                    channel.users.remove(lowered_old_nick);
                }
            }
        });

    enum UserChannelFlag[char] mode_chars =
        ['v': UserChannelFlag.VOICE,
         'h': UserChannelFlag.HOP,
         'o': UserChannelFlag.OP,
         'a': UserChannelFlag.ADMIN,
         'q': UserChannelFlag.OWNER];

    m.listeners["MODE"] = new Listener(
        function void(Client c, in char[] source, in char[][] args, in char[] message)
        {
            //string lowered_nick = source.get_nick().toLower().idup;
            //c.send_privmsg("#fusxbottest", "MODE " ~ args.join(' '));

            if (args[0].is_channel())
            {
                Channel* channel = args[0].toLower().idup in c.channels;
                assert(channel);

                const(char[])[] mode_args = void;
                if (args.length >= 3) mode_args = args[2..$];
                else mode_args = null;

                bool currently_adding;
                assert(args[1][0] == '+' || args[1][0] == '-');
                foreach (char chr; args[1])
                {
                    switch (chr)
                    {
                        case '+':
                            currently_adding = true;
                            break;

                        case '-':
                            currently_adding = false;
                            break;

                        case 'v': case 'h': case 'o': case 'a': case 'q':
                            assert(mode_args);
                            LocalUser* user = mode_args[0].toLower().idup in channel.users;
                            assert(user);

                            if (currently_adding)
                            {
                                assert(!(mode_chars[chr] & user.user_channel_flags));
                                user.user_channel_flags |= mode_chars[chr];
                            }
                            else
                            {
                                assert(mode_chars[chr] & user.user_channel_flags);
                                user.user_channel_flags ^= mode_chars[chr];
                            }

                            if (mode_args.length > 1) mode_args = mode_args[1..$];
                            else mode_args = null;
                            break;

                        case 'b': case 'e': case 'I':
                            assert(mode_args);
                            if (mode_args.length > 1) mode_args = mode_args[1..$];
                            else mode_args = null;
                            break;

                        default:
                            break;
                    }
                }

                assert(!mode_args);
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
                    const(char)[] channel_name = in_channel ? args[0] : nick;

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
                        if (!guser)
                        {
                            guser = &(c.users[lowered_nick] = GlobalUser(nick.idup));
                            guser.ref_count = 0;
                        }
                        assert(guser);
                        assert(guser == (lowered_nick in c.users));
                    }

                    void check_auth_and_run_command(int depth = 1)
                    {
                        void ns_verify_and_rerun_command()
                        {
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
                                            assert(!((lowered_nick in c.users) && (guser.ref_count < 1)));
                                            if (lowered_nick !in c.users)
                                            {
                                                guser = &(c.users[lowered_nick] = GlobalUser(nick.idup));
                                                guser.ref_count = 0;
                                            }

                                            assert((lowered_nick in c.users) is guser);
                                            guser.ns_status = to!byte(s[2]);
                                            assert(guser.ns_status >= 0 && guser.ns_status <= 3);

                                            if (auto ovr = lowered_nick in c.config.auth_level_overrides)
                                            {
                                                if (guser.ns_status >= ovr.min_ns_status)
                                                {
                                                    guser.auth_level = ovr.auth_level;
                                                }
                                            }

                                            check_auth_and_run_command(depth + 1);
                                            return TLOption.DONE;
                                        }
                                    }
                                    return TLOption.QUEUE;
                                });
                        }

                        scope(exit)
                        {
                            assert(!(in_channel && guser.ref_count == 0));
                            if (!in_channel && guser.ref_count == 0)
                                c.users.remove(lowered_nick);
                        }

                        if (in_channel && user.user_channel_flags < cmd.min_channel_auth_level)
                        {
                            c.send_privmsg(channel_name, "Error - your channel auth level "
                                           "is too low to use this command.");
                            return;
                        }
                        if (guser.auth_level < cmd.min_auth_level)
                        {
                            if (depth <= 1)
                                ns_verify_and_rerun_command();
                            else
                                c.send_privmsg(channel_name, "Error - you are not allowed to use this command.");
                            return;
                        }
                        if (guser.ns_status < cmd.min_ns_status)
                        {
                            if (depth <= 1)
                                ns_verify_and_rerun_command();
                            else
                                c.send_privmsg(args[0], "Error - you must be identified to use this command.");
                            return;
                        }

                        cmd.f(c, source, channel_name, msg[1]);
                    }

                    check_auth_and_run_command();
                }
            }
        });
}
