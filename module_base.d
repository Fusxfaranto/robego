
public import irc;
public import util;

enum ChannelRestriction
{
    CHAN,
    PM,
    BOTH,
}

struct Command
{
    void function(Client, string, string, string) f;
    byte min_ns_status = -1;
    UserChannelFlag min_channel_auth_level = UserChannelFlag.NONE;
    ubyte min_auth_level = 50;
    ChannelRestriction channel_restriction = ChannelRestriction.BOTH;
}

struct Listener
{
    void function(Client, string, string[], string) f;
    bool enabled = true;
    string name = "";
}

struct IRCModule
{
    Listener*[string] listeners;
    Command*[string] commands;
    // TODO: is first_time really necessary, or can modules figure that out themselves
    void function(ref Variant[string], bool /* first_time */) initialize = null;
}
