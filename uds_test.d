import io = std.stdio : writeln, writefln;
import std.conv : to;
import socket = std.socket : Socket, UnixAddress, AddressFamily, SocketType, SocketShutdown, SocketSet;//, Address, getAddress
//import std.socketstream : SocketStream;
import core.thread : sleep;
import std.file : exists, remove;

debug = 1;

immutable string sock_filename = "./sock";


void main()
{
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

    Socket uds_socket = uds_server.accept();
    
    SocketSet sockset = new SocketSet();
    sockset.add(uds_socket);

    char[512] uds_buf = '\0';
    long n;
    while (true)
    {
        Socket.select(sockset, null, null);
        assert(sockset.isSet(uds_socket));
        n = uds_socket.receive(uds_buf);
        writeln(n);
        if (n != Socket.ERROR && n != 0)
        {
            writeln(uds_buf);
            uds_buf[0..n] = '\0';
        }
        else
        {
            sleep(2);
        }
        writeln();
    }
}


