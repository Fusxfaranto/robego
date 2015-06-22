
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

*/
