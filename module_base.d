
public import irc;
public import util;

struct Command
{
    void function(Client, in char[], in char[], in char[]) f;
    byte min_ns_status = -1;
    UserChannelFlag min_channel_auth_level = UserChannelFlag.NONE;
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
    void function(ref Variant[string]) initialize = null;
}
