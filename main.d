import io = std.stdio : writeln, writefln, stdout;
import std.conv : to;
import std.socket;
//import std.socketstream : SocketStream;
import core.thread : sleep/*, dur*/;
import std.file : exists, remove;

import util;
import irc_commands;

debug = 1;


immutable string sock_filename = "./sock";
immutable int IRC_BUF_LEN = 512;
immutable int UDS_BUF_LEN = 512;


struct irc_state_t
{
    bool ready = false;
}

void process_line(ref irc_state_t state, ref Socket s, in char[] line)
{
    const char[][2] splitted_line = split1(line, ':');
    debug writeln(line);
    //debug writeln(splitted_line);
    
    switch (splitted_line[0])
    {
        default:
            break;
        case "PING":
            send_raw(s, "PONG :" ~ splitted_line[1]);
            debug writeln("<1> sent pong");
            if (!state.ready)
            {
                state.ready = true;
                send_raw(s, "JOIN :#fusxbottest");
            }
            break;
    }
}

void extract_run_lines(ref irc_state_t state, ref Socket s, ref char[IRC_BUF_LEN] buf, long len, ref char[] extra)
{
    int index = -1;
    bool has_r = (extra.length && extra[$ - 1] == '\r');

    if (buf[0] == '\n')
    {
        process_line(state, s, extra[0..($ - has_r)]);
        index = 1;
    }

    for (int i = 1; i < len; i++)
    {
        if (buf[i] == '\n')
        {
            if (buf[i - 1] == '\r')
                has_r = true;
            else
                has_r = false;

            //debug writeln(to!string(index) ~ ' ' ~ to!string(i));
            if (index == -1)
                process_line(state, s, extra ~ buf[0..(i - has_r)]);
            else
                process_line(state, s, buf[index..(i - has_r)]);
            
            index = i + 1;
        }
    }
    
    if (index == -1)
        extra ~= buf;
    else
        extra = buf[index..len].dup;
    //debug writeln("extra: " ~ extra);
}

void main()
{
    auto sockset = new SocketSet(8);
    
    // init irc_socket
    auto irc_socket = new Socket(AddressFamily.INET, SocketType.STREAM);
    scope(exit)
    {
        irc_socket.shutdown(SocketShutdown.BOTH);
        irc_socket.close();
    }
    
    irc_socket.blocking(true);
    sockset.add(irc_socket);


    // init uds_server and uds_socket
    bool uds_connected = false;
    auto uds_server = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    scope(exit)
    {
        uds_server.shutdown(SocketShutdown.BOTH);
        uds_server.close();
        remove(sock_filename);
    }
    
    uds_server.blocking(true);

    if (exists(sock_filename)) remove(sock_filename);
    uds_server.bind(new UnixAddress(sock_filename));

    uds_server.listen(1);

    Socket uds_socket;
    scope(exit)
    {
        uds_socket.shutdown(SocketShutdown.BOTH);
        uds_socket.close();
    }

    
    // connect irc socket
    Address addr = getAddress("irc.synirc.net", 6667)[0];
    writeln(addr);
    irc_socket.connect(addr);
    writeln("connected!");
    writeln();

    
    // init irc state
    irc_state_t irc_state;
    send_raw(irc_socket, "NICK Robego");
    send_raw(irc_socket, "USER Robego 0 * :Robego");
    
    
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
            extract_run_lines(irc_state, irc_socket, irc_buf, irc_n, irc_extra);
            //debug writeln();
            //debug writeln();
            //writeln(irc_socket.send(buf));
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

                send_raw(irc_socket, "PRIVMSG #fusxbottest :" ~ uds_buf[0..uds_n]);
            
                uds_buf[0..uds_n] = 0;
            }
        }
    }
     
}
