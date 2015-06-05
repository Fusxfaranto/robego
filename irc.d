debug(prof) debug = 1;

import io = std.stdio : writeln, writefln, stdout;
import std.conv : to;
import std.socket;
import core.thread : sleep/*, dur*/;
import std.file : exists, remove;
import std.array : split, appender;
//import std.container.dlist : DList;
debug(prof) import std.datetime : StopWatch;

import util;
import irc_commands;
import module_base;
public import delayed_action;


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
        Command[string] commands;
        Listener[][string] listeners;

        debug(prof) StopWatch sw;

        
    public:
        string nick = "Robego";
        string username = "Robego";
        string realname = "Robego";
        string[] channels = ["#fusxbottest"];

        auto delayed_actions = new SortedList!(DelayedAction, "a.time < b.time");
        
        bool ready = false;
        bool uds_connected = false;
        Socket irc_socket;
        Socket uds_server;
        Socket uds_socket;
        
        this()
        {
            reload();

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
                auto t = getAddress("irc.synirc.net", 6667);
                assert(t.length);
                addr = t[0];
            }
            debug writeln(addr);
            irc_socket.connect(addr);
            debug writeln("connected!");
            debug writeln();

    
            // init rest of irc state
            send_raw("NICK " ~ nick);
            send_raw("USER " ~ username ~ " 0 * :" ~ realname);
        }

        ~this()
        {
            debug writeln("Client destructor");
            unload_dynamics(commands, listeners);
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

        void reload()
        {
            reload_dynamics(commands, listeners);
            debug writeln(commands);
            debug writeln(listeners);
            debug if (ready) send_raw("PRIVMSG #fusxbottest :reloaded");
        }

        void send_raw(in char[] line)
        {
            debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
            assert(line.length < 510);
            assert(irc_socket.send(line ~ "\r\n") == line.length + 2);
            debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
        }

        void process_line(in char[] line)
        {
            debug writeln(line);
            debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);

            auto index = 0; // TODO: is this the proper type?
            //pragma(msg, typeof(index));
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

            if (command == "PING")
            {
                send_raw("PONG :" ~ message);
                debug writeln("sent pong");
                if (!ready)
                {
                    ready = true;
                    send_raw("JOIN :#fusxbottest"); // TODO: configureable channels
                }
                return;
            }
            if (command == "PRIVMSG" && message.length >= 2 && message[0] == COMMAND_CHAR)
            {
                if (Command* p = message[1..$] in commands)
                {
                    debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
                    (*p).f(this, source, message);
                    debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
                }
            }

            if (Listener[]* p = command in listeners)
            {
                debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
                foreach (f; *p)
                    f.f(this, source, args, message);
                debug(prof) writeln(__LINE__, ' ', sw.peek().usecs);
            }
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

                    //debug writeln(to!string(index) ~ ' ' ~ to!string(i));
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
            //debug writeln("extra: " ~ extra);
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
                    debug if (irc_n == 333) break;
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

                        send_raw("PRIVMSG #fusxbottest :" ~ uds_buf[0..uds_n]);
            
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
                    }
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
