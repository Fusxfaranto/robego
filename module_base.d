
public import irc;

struct Command
{
    // TODO: implement permissions
    void function(Client, in char[], in char[]) f;
}

struct Listener
{
    // TODO: implement disableability
    void function(Client, in char[], in char[][], in char[]) f;
}

struct IRCModule
{
    Listener[string] listeners;
    Command[string] commands;
}
