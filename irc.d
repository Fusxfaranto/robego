debug(prof) debug = 1;

import io = std.stdio : writeln, writefln, stdout;
import std.conv : to;
import std.socket;
import core.thread : sleep/*, dur*/;
import std.file : exists, remove;
import std.array : split, appender, join;
import std.algorithm : remove;
import std.container : DList;
import std.variant : Variant;
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


final class Client
{
private:
    SocketSet sockset;

    debug(prof) StopWatch sw;

        
public:
    string nick;
    string username;
    string realname;
    string network;
    string[] initial_channels;

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
        
    this(string n, string u, string r, string w, string[] c)
    {
        nick = n;
        username = u;
        realname = r;
        network = w;
        initial_channels = c;

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
            auto t = getAddress(network, 6667);
            assert(t.length);
            addr = t[0];
        }
        debug writeln(addr);
        irc_socket.connect(addr);
        debug writeln("connected!");
        debug writeln();

    
        // init rest of irc state
        send_raw("NICK ", nick);
        send_raw("USER ", username, " 0 * :", realname);


        reload();
    }

    ~this()
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

    void send_raw(in char[] line)
    {
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
        assert(line.length < 510);
        assert(irc_socket.send(line ~ "\r\n") == line.length + 2);
        debug writeln("sent -- ", line);
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
    }

    void send_raw(in char[][] line ...)
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
        debug writeln(module_data);
        //debug if (ready) send_raw("PRIVMSG #fusxbottest :reloaded");
    }

    void process_line(in char[] line)
    {
        debug writeln(line);
        debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);

        size_t index = 0;
        const(char)[] source;
        if (line[0] == ':')
        {
            for (index = 1; /*index < line.length &&*/ line[index] != ' '; index++) {}
            source = line[1..index];
            index++;
        }
        else source = "";

        const(char)[] command;
        auto prev_index = index;
        for (; line[index] != ' '; index++) {}
        command = line[prev_index..index];
        index++;

        const(char)[][] args;
        auto args_appender = appender(args);
        while (index < line.length && line[index] != ':')
        {
            prev_index = index;
            for (; index < line.length && line[index] != ' '; index++) {}
            args_appender.put(line[prev_index..index]);
            index++;
        }
        args = args_appender.data;

        const(char)[] message;
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
                        waiting_on_tl_queue.insertBack(TLWaitingAction(f, source.dup,
                                                                       args.dup_elems, message.dup));
                    }
                    else
                    {
                        f.f(this, source, args, message);
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
                    f.f(this, source, args, message);
                }
            }
        }

        void queue_listeners()
        {
            if (Listener*[]* p = command in listeners)
            {
                foreach (f; *p)
                {
                    waiting_on_tl_queue.insertBack(TLWaitingAction(f, source.dup,
                                                                   args.dup_elems, message.dup));
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
                        a.f.f(this, a.source, a.args, a.message);
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
                        a.f.f(this, a.source, a.args, a.message);
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
            process_line(extra[0..($ - has_r)]);
            index = 1;
        }

        for (int i = 1; i < len; i++)
        {
            if (buf[i] == '\n')
            {
                has_r = buf[i - 1] == '\r';

                if (index == -1)
                    process_line(extra ~ buf[0..(i - has_r)]);
                else
                    process_line(buf[index..(i - has_r)]);
            
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

                    send_raw("PRIVMSG #fusxbottest :", uds_buf[0..uds_n]);
            
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


void send_privmsg(Client c, in char[] channel, in char[] message)
{
    c.send_raw("PRIVMSG ", channel, " :", message);
}

void send_privmsg(Client c, in char[] channel, in char[][] message_parts ...)
{
    c.send_raw("PRIVMSG ", channel, " :", message_parts.join());
}

void send_join(Client c, in char[] channel)
{
    c.send_raw("JOIN :", channel);
}

void send_join(Client c, in char[][] channels)
{
    c.send_raw("JOIN :", channels.join(','));
}

void send_part(Client c, in char[] channel)
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
