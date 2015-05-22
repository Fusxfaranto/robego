
public import irc : Client;

alias listener_t = void function(Client, in char[], in char[][], in char[]);
alias command_t = void function(Client, in char[], in char[]);

// TODO: figure out why using the aliases doesn't work for these ???
struct IRCModule
{
    void function(Client, in char[], in char[][], in char[])[string] listeners;
    void function(Client, in char[], in char[])[string] commands;
}
