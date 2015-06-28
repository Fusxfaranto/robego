
public import irc;
public import util;

struct Command
{
    void function(Client, in char[], in char[], in char[]) f;
    byte min_ns_status = -1;
    channel_auth_t min_channel_auth_level = channel_auth_t.NONE;
    ubyte min_auth_level = 50;
}

struct Listener
{
    void function(Client, in char[], in char[][], in char[]) f;
}

struct IRCModule
{
    Listener*[string] listeners;
    Command*[string] commands;
}

/*

*/
