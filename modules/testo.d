// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.stdio;

int* testo_int;
int[]* testo_array;

static this()
{
    writeln("testo module constructor");

    m.initialize = function void(ref Variant[string] module_data)
        {
            writeln("testo init function");
            module_data.register_module_data!testo_int(5554);
            module_data.register_module_data!testo_array([67, 1434]);
        };

    m.commands["testo"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            writeln("testo command");
            writeln(source);
            writeln(channel);
            writeln(message);
            writeln(testo_int);
            *testo_int = 14141;
            c.send_raw("PRIVMSG #fusxbottest :", channel, ": <", source, "> ", message/*, " poop"*/);
            c.delayed_actions.insert(new DelayedCallback({writeln("lazy");}));
            c.delayed_actions.insert(new DelayedCallback({c.send_raw("PRIVMSG #fusxbottest :poop");}, 10000));
        }, -1, UserChannelFlag.NONE, 0);

    m.commands["testo2"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            writeln(c.module_data);
            writeln(testo_int);
            writeln(c.module_data["testo_int"].peek!int());
            c.module_data["testo_int"] = 14141;
        }, -1, UserChannelFlag.NONE, 0);

    m.commands["testo3"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            writeln(testo_array);
            writeln(*testo_array);
            writeln(testo_array.ptr);
            *testo_array = [6, 2, 5, 23];
        }, -1, UserChannelFlag.NONE, 0);

    m.commands["testo4"] = new Command(
        function void(Client c, in char[] source, in char[] channel, in char[] message)
        {
            c.send_privmsg("NickServ", "STATUS Robego");
            assert(!c.temporary_listener.action);
            alias source_ = source;
            alias channel_ = channel;
            alias message_ = message;
            c.temporary_listener = TemporaryListener(
                delegate TLOption(in char[] source, in char[] command, in char[][] args, in char[] message)
                {
                    if (command == "NOTICE" && source.get_nick() == "NickServ")
                    {
                        auto s = message.splitN!2(' ');
                        if (s[0] == "STATUS" && s[1] == "Robego")
                        {
                            import core.memory : GC;
                            writeln(source.ptr, ' ', GC.query(source.ptr));
                            writeln(source_.ptr, ' ', GC.query(source_.ptr));
                            return TLOption.DONE;
                        }
                    }
                    return TLOption.QUEUE;
                });
        }, -1, UserChannelFlag.NONE, 0);
}

static ~this()
{
    writeln("testo module destructor");
}
