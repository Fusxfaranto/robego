debug(prof) debug = 1;

import io = std.stdio : writeln, writefln, stdout;
import std.conv : to;
import std.socket;
import core.thread : sleep/*, dur*/;
import std.file : exists, remove, readText;
import std.array : split, appender, join;
import std.algorithm : remove;
import std.container : DList;
import std.variant : Variant;
import std.json : /*JSONValue, */parseJSON;
import std.uni : toLower;
debug(prof) import std.datetime : StopWatch;

import util;
import irc_commands;
import module_base;
public import delayed_action;
public import user;


enum string SOCK_FILENAME = "./sock";
enum int IRC_BUF_LEN = 512;
enum int UDS_BUF_LEN = 512;
enum char COMMAND_CHAR = ',';
enum long SELECT_WAIT_MICROSECONDS = 0;
enum long SELECT_WAIT_SECONDS = 1;




struct UserChannelFlag_
{
    UserChannelFlag f;
    alias f this;

    this(in JSONValue json)
    {
        f = auth_chars[json.str()[0]];
    }

    this(UserChannelFlag f_)
    {
        f = f_;
    }
}


final class Client
{
private:
    SocketSet sockset;

    debug(prof) StopWatch sw;

        
public:
    struct Config
    {
        // TODO: keep these up with network state (i.e. take out of config)
        string nick;
        string username;
        string realname;
        string network;
        ushort port;
        string[] initial_channels;

        struct AuthLevelOverride
        {
            ubyte auth_level;
            byte min_ns_status;
        }
        AuthLevelOverride[string] auth_level_overrides;

        struct RoomOverride
        {
            bool[string] listeners;

            struct CommandParams
            {
                byte min_ns_status;
                UserChannelFlag_ min_channel_auth_level;
                ubyte min_auth_level;
            }
            CommandParams[string] commands;
        }
        RoomOverride[string] room_overrides;
    }
    Config config;

    UserChannelFlag_[string][string] channel_auth_overrides;

    GlobalUser[string] users;
    Channel[string] channels;

    Command*[string] commands;
    Listener*[][string] listeners;
    Variant[string] module_data;

    auto delayed_actions = new SortedList!(DelayedAction, "a.time <= b.time");

    TemporaryListener temporary_listener;
    DList!(TLWaitingAction) waiting_on_tl_queue;
        
    bool ready = false;
    bool uds_connected = false;
    Socket irc_socket;
    Socket uds_server;
    Socket uds_socket;
        
    this(string config_filename)
    {
        config = static_json!Config(parseJSON(readText(config_filename)));
        channel_auth_overrides = static_json!(UserChannelFlag_[string][string])(
            parseJSON(readText("channel_auth_overrides.json")));

        sockset = new SocketSet(8); // TODO: figure out why this needs to be 8
        // init irc_socket
        irc_socket = new Socket(AddressFamily.INET, SocketType.STREAM);
    
        irc_socket.blocking(true);
        sockset.add(irc_socket);


        // init uds_server and uds_socket
        uds_connected = false;
        uds_server = new Socket(AddressFamily.UNIX, SocketType.STREAM);
            
        uds_server.blocking(true);

        if (exists(SOCK_FILENAME)) remove(SOCK_FILENAME);
        uds_server.bind(new UnixAddress(SOCK_FILENAME));

        uds_server.listen(1);


        // connect irc socket
        Address addr;
        {
            auto t = getAddress(config.network, config.port);
            assert(t.length);
            addr = t[0]; // TODO: do something else than just pick the first one?
        }
        debug writeln(addr);
        irc_socket.connect(addr);
        debug writeln("connected!");
        debug writeln();

    
        // init rest of irc state
        send_raw("NICK ", config.nick);
        send_raw("USER ", config.username, " 0 * :", config.realname);


        reload();
    }

    ~this()
    //void destroy_client()
    {
        debug writeln("Client destructor");
        unload_dynamics(commands, listeners);
        debug writeln("unloaded dynamics");
        assert(irc_socket);
        irc_socket.shutdown(SocketShutdown.BOTH);
        irc_socket.close();
        assert(uds_server);
        uds_server.shutdown(SocketShutdown.BOTH);
        uds_server.close();
        remove(SOCK_FILENAME);
        if (uds_socket)
        {
            uds_socket.shutdown(SocketShutdown.BOTH);
            uds_socket.close();
        }
        debug writeln("finished Client destructor");
        debug stdout.flush();
    }

    void send_raw(string line)
    {
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
        assert(line.length < 510);
        assert(irc_socket.send(line ~ "\r\n") == line.length + 2);
        debug writeln("sent -- ", line);
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
    }

    void send_raw(string[] line ...)
    {
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
        foreach (part; line)
        {
            assert(part.length < 510);
            assert(irc_socket.send(part) == part.length);
        }
        assert(irc_socket.send("\r\n") == 2);
        debug writeln("sent -- ", line.join());
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
    }

    void reload()
    {
        reload_dynamics(module_data, commands, listeners);
        debug writeln(commands);
        debug writeln(listeners);
        //debug writeln(module_data);
        //debug if (ready) send_raw("PRIVMSG #fusxbottest :reloaded");
    }

    void run_listener(ref Listener f, string source, string[] args, string message)
    {
        bool enabled = f.enabled;
        if (args.length > 0)
        {
            if (auto room_override = args[0].toLower() in config.room_overrides)
            {
                if (auto ovr = f.name in room_override.listeners)
                {
                    enabled = *ovr;
                }
            }
        }

        if (enabled)
        {
            f.f(this, source, args, message);
        }
    }

    void process_line(string line)
    {
        debug writeln(line);
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);

        size_t index = 0;
        string source;
        if (line[0] == ':')
        {
            for (index = 1; /*index < line.length &&*/ line[index] != ' '; index++) {}
            source = line[1..index];
            index++;
        }
        else source = "";

        string command;
        auto prev_index = index;
        for (; line[index] != ' '; index++) {}
        command = line[prev_index..index];
        index++;

        string[] args;
        auto args_appender = appender(args);
        while (index < line.length && line[index] != ':')
        {
            prev_index = index;
            for (; index < line.length && line[index] != ' '; index++) {}
            args_appender.put(line[prev_index..index]);
            index++;
        }
        args = args_appender.data;

        string message;
        if (index < line.length) message = line[(index + 1)..$];
        else message = "";

        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);

        /*debug
          {
          write("source:  "); writeln(source);
          write("command: "); writeln(command);
          write("args:    "); writeln(args);
          write("message: "); writeln(message);
          writeln();
          }*/

        void run_queue_listeners()
        {
            if (Listener*[]* p = command in listeners)
            {
                foreach (f; *p)
                {
                    if (temporary_listener.action)
                    {
                        waiting_on_tl_queue.insertBack(
                            TLWaitingAction(f, source.dup,args.idup_elems, message.dup));
                    }
                    else
                    {
                        run_listener(*f, source, args, message);
                    }
                }
            }
        }

        void run_listeners()
        {
            if (Listener*[]* p = command in listeners)
            {
                foreach (f; *p)
                {
                    run_listener(*f, source, args, message);
                }
            }
        }

        void queue_listeners()
        {
            if (Listener*[]* p = command in listeners)
            {
                foreach (f; *p)
                {
                    waiting_on_tl_queue.insertBack(
                        TLWaitingAction(f, source.dup,args.idup_elems, message.dup));
                }
            }
        }


        if (temporary_listener.action)
        {
            auto x = temporary_listener.action(source, command, args, message);
            writeln(x);
            final switch (x)
            {
            case TLOption.QUEUE:
                queue_listeners();
                return;

            case TLOption.DONE:
                temporary_listener.action = null;
                while (!waiting_on_tl_queue.empty())
                {
                    TLWaitingAction* a = &waiting_on_tl_queue.front();
                    run_listener(*a.f, source, args, message);
                    waiting_on_tl_queue.removeFront();
                    if (temporary_listener.action)
                    {
                        queue_listeners();
                        return;
                    }
                }
                break;

            case TLOption.RUN_THIS:
                run_listeners();
                return;

            case TLOption.RUN_DONE:
                run_listeners();
                debug writeln(users);
                debug writeln(channels);
                temporary_listener.action = null;
                while (!waiting_on_tl_queue.empty())
                {
                    TLWaitingAction* a = &waiting_on_tl_queue.front();
                    debug writeln(*a);
                    run_listener(*a.f, source, args, message);
                    waiting_on_tl_queue.removeFront();
                    if (temporary_listener.action)
                    {
                        queue_listeners();
                        return;
                    }
                }
                return;
            }
        }

        run_queue_listeners();
    }

    void extract_run_lines(ref char[IRC_BUF_LEN] buf, in long len, ref char[] extra)
    {
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
        int index = -1;
        bool has_r = (extra.length && extra[$ - 1] == '\r');

        if (buf[0] == '\n')
        {
            process_line(extra[0..($ - has_r)].idup);
            index = 1;
        }

        for (int i = 1; i < len; i++)
        {
            if (buf[i] == '\n')
            {
                has_r = buf[i - 1] == '\r';

                if (index == -1)
                {
                    if (extra.length)
                    {
                        //debug writeln("extra: ", extra);
                        process_line((extra ~ buf[0..(i - has_r)]).idup);
                    }
                    else
                    {
                        process_line(buf[0..(i - has_r)].idup);
                    }
                }
                else
                {
                    process_line(buf[index..(i - has_r)].idup);
                }
            
                index = i + 1;
            }
        }
    
        if (index == -1)
            extra ~= buf;
        else
            extra = buf[index..len].dup;
    }
        
    void run_loop()
    {
        char[IRC_BUF_LEN] irc_buf = 0;
        char[UDS_BUF_LEN] uds_buf = 0;
        debug writeln(irc_buf.ptr);
        char[] irc_extra = "".dup;
        long irc_n, uds_n;
        TimeVal select_wait_time;
        select_wait_time.microseconds = SELECT_WAIT_MICROSECONDS;
        select_wait_time.seconds = SELECT_WAIT_SECONDS;
        while (true)
        {
            Socket.select(sockset, null, null, &select_wait_time);
            if (sockset.isSet(irc_socket))
            {
                debug(prof) sw.start();
                irc_n = irc_socket.receive(irc_buf);
                assert(irc_n > 0);

                debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
        
                //debug writeln();
                //debug writeln(n);
                //debug writeln(buf/*[0..n]*/);
                extract_run_lines(irc_buf, irc_n, irc_extra);
                debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
                //debug writeln();
                //debug writeln();
                //writeln(irc_socket.send(buf));
                //debug if (irc_n == 333) break;
            }
            if (!uds_connected && sockset.isSet(uds_server))
            {
                uds_socket = uds_server.accept();
                uds_connected = true;
            }
            if (uds_connected && sockset.isSet(uds_socket))
            {
                uds_n = uds_socket.receive(uds_buf);
                assert(irc_n != -1);
                if (uds_n == 0)
                {
                    uds_connected = false;
                }
                else
                {
                    writeln();
                    writeln("uds: ");
                    writeln(uds_n);
                    writeln(uds_buf);
                    writeln();

                    send_raw("PRIVMSG #fusxbottest :", uds_buf[0..uds_n].idup);
            
                    uds_buf[0..uds_n] = 0;
                }
            }

            while (delayed_actions.has_items() &&
                   delayed_actions.front.time < MonoTime.currTime())
            {
                DelayedAction action = delayed_actions.front();
                if (cast(DelayedQuit) action)
                {
                    debug writeln("quitting from DelayedQuit");
                    return;
                }
                else if (cast(DelayedReload) action)
                {
                    debug writeln("reloading from DelayedReload");
                    reload();
                    debug writeln("reloaded");
                }
                else if (auto a = cast(DelayedCallback) action)
                {
                    debug writeln("running callback from DelayedCallback");
                    a.cb();
                    debug writeln("finished callback");
                }/*
                   else if (auto a = cast(DelayedEval) action)
                   {
                   debug writeln("evaling from DelayedEval");
                   bool res = load_and_run(a.args);
                   if (res)
                   this.send_privmsg(a.args[4], "done evaling");
                   else
                   this.send_privmsg(a.args[4], "error compiling");
                   debug writeln("finished evaling");
                   }*/
                else assert(0, "no matching type in delayed_queue");

                delayed_actions.pop();
            }

            sockset.reset();
            sockset.add(irc_socket);
            if (uds_connected)
                sockset.add(uds_socket);
            else
                sockset.add(uds_server);

            select_wait_time.microseconds = SELECT_WAIT_MICROSECONDS;
            select_wait_time.seconds = SELECT_WAIT_SECONDS;

            debug(prof)
                if (sw.running())
                {
                    sw.stop();
                    writeln(__LINE__, ' ', sw.peek().usecs);
                    writeln();
                    stdout.flush();
                    sw.reset();
                }

            debug stdout.flush();
        }
    }
}


void send_privmsg(Client c, string channel, string message)
{
    c.send_raw("PRIVMSG ", channel, " :", message);
}

void send_privmsg(Client c, string channel, string[] message_parts ...)
{
    c.send_raw("PRIVMSG ", channel, " :", message_parts.join());
}

void send_join(Client c, string channel)
{
    c.send_raw("JOIN :", channel);
}

void send_join(Client c, string[] channels)
{
    c.send_raw("JOIN :", channels.join(','));
}

void send_part(Client c, string channel)
{
    c.send_raw("PART :", channel);
    //c.channels.remove(channel.idup);
}


void register_module_data(alias var, T = typeof(*var), string name = var.stringof)
    (ref Variant[string] module_data, T value = T.init) if (is(typeof(*var)))
{
    Variant* p = name in module_data;
    if (!p)
    {
        module_data[name] = value;
        p = name in module_data;
        assert(p);
    }
    assert(typeid(T) == p.type);
    var = p.peek!T();
    assert(var);
}
