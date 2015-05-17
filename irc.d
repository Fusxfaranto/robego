import io = std.stdio : writeln, writefln, stdout;
import std.conv : to;
import std.socket;
import core.thread : sleep/*, dur*/;
import std.file : exists, remove;
import std.array : split, appender;
import std.container.dlist : DList;

import util;
import irc_commands;
import module_base;



immutable string SOCK_FILENAME = "./sock";
immutable int IRC_BUF_LEN = 512;
immutable int UDS_BUF_LEN = 512;
immutable char COMMAND_CHAR = ',';


// TODO: make "final class"?
class Client
{
    private:
        SocketSet sockset;
        command_t[string] commands;
        listener_t[][string] listeners;

        auto lazy_queue = DList!(void delegate())();

        
    public:
        string nick = "Robego";
        string username = "Robego";
        string realname = "Robego";
        string[] channels = ["#fusxbottest"];
        
        bool ready = false;
        bool uds_connected = false;
        bool will_quit = false;
        Socket irc_socket;
        Socket uds_server;
        Socket uds_socket;
        
        this()
        {
            reload();

            sockset = new SocketSet(8);
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
            writeln(addr);
            irc_socket.connect(addr);
            writeln("connected!");
            writeln();

    
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

        void push_lazy_queue(void delegate() exp)
        {
            lazy_queue.insertBack(exp);
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
            assert(line.length < 510);
            assert(irc_socket.send(line ~ "\r\n") == line.length + 2);
        }

        void process_line(in char[] line)
        {
            debug writeln(line);

            auto index = 0; // TODO: is this the proper type?
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

            /*debug
              {
              write("source:  "); writeln(source);
              write("command: "); writeln(command);
              write("args:    "); writeln(args);
              write("message: "); writeln(message);
              writeln();
              }*/

            // TODO: exec listeners

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
                if (command_t* p = message[1..$] in commands)
                {
                    (*p)(this, source, message);
                }
                if (message == ",asdf")
                {
                    import core.runtime;
                    Runtime.terminate();
                }
            }

/*            if (splitted_line[0] == "PING")
              {
              send_raw("PONG " ~ splitted_line[1]);
              debug writeln("sent pong");
              if (!ready)
              {
              ready = true;
              send_raw("JOIN :#fusxbottest"); // TODO: configureable channels
              }
              return;
              }
              if (splitted_line[1] == "PRIVMSG" && splitted_line[3].length >= 3
              && splitted_line[3][1] == COMMAND_CHAR)
              {
              if (command* p = splitted_line[3][2..$] in commands)
              {
              (*p)(this, "fff", "aaa");
              }
              }*/
        }

        void extract_run_lines(ref char[IRC_BUF_LEN] buf, in long len, ref char[] extra)
        {
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
            // main loop
            char[IRC_BUF_LEN] irc_buf = 0;
            char[UDS_BUF_LEN] uds_buf = 0;
            char[] irc_extra = "".dup;
            long irc_n, uds_n;
            while (true)
            {
                scope(exit)
                {
                    sockset.reset();
                    sockset.add(irc_socket);
                    if (uds_connected)
                        sockset.add(uds_socket);
                    else
                        sockset.add(uds_server);  
                }
        
                assert(Socket.select(sockset, null, null) > 0);
                if (sockset.isSet(irc_socket))
                {
                    irc_n = irc_socket.receive(irc_buf);
                    assert(irc_n > 0);
        
                    //debug writeln();
                    //debug writeln(n);
                    //debug writeln(buf/*[0..n]*/);
                    extract_run_lines(irc_buf, irc_n, irc_extra);
                    //debug writeln();
                    //debug writeln();
                    //writeln(irc_socket.send(buf));
                    import core.runtime;
                    if (irc_n == 333) break;
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

                while (!lazy_queue.empty())
                {
                    lazy_queue.front()();
                    lazy_queue.removeFront();
                }

                if (will_quit)
                {
                    debug send_raw("QUIT :quitting from will_quit");
                    debug writeln("quitting from will_quit");
                    break;
                }

                debug stdout.flush();
            }
        }
}
