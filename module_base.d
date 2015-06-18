
public import irc;
public import util;

struct Command
{
    // TODO: implement permissions
    void function(Client, in char[], in char[], in char[]) f;
}

struct Listener
{
    void function(Client, in char[], in char[][], in char[]) f;
    bool enabled = true;
}

struct IRCModule
{
    Listener*[string] listeners;
    Command*[string] commands;
}

/*
            c.temporary_listeners ~= TemporaryListener(
                delegate bool(in char[] source, in char[] command, in char[][] args, in char[] message)
                {
                    return
                },
                delegate void(in char[] source, in char[] command, in char[][] args, in char[] message)
                {

                });
*/
