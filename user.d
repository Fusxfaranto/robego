
enum UserChannelFlag : uint {NONE = 0x0, VOICE = 0x1, HOP = 0x2, OP = 0x4, ADMIN = 0x8, OWNER = 0x10}

enum UserChannelFlag[char] auth_chars =
    [
        '*': UserChannelFlag.NONE, // not a standard symbol, is there something better?
        '+': UserChannelFlag.VOICE,
        '%': UserChannelFlag.HOP,
        '@': UserChannelFlag.OP,
        '&': UserChannelFlag.ADMIN,
        '~': UserChannelFlag.OWNER,
        ];

enum UserChannelFlag[char] input_auth_chars =
    [
        '*': UserChannelFlag.NONE,
        '+': UserChannelFlag.VOICE,
        '%': UserChannelFlag.HOP,
        '@': UserChannelFlag.OP,
        '&': UserChannelFlag.ADMIN,
        '~': UserChannelFlag.OWNER,

        'v': UserChannelFlag.VOICE,
        'h': UserChannelFlag.HOP,
        'o': UserChannelFlag.OP,
        'a': UserChannelFlag.ADMIN,
        'q': UserChannelFlag.OWNER,
        ];

enum char[UserChannelFlag] auth_chars_by_level =
    [
        UserChannelFlag.NONE: '*',
        UserChannelFlag.VOICE: '+',
        UserChannelFlag.HOP: '%',
        UserChannelFlag.OP: '@',
        UserChannelFlag.ADMIN: '&',
        UserChannelFlag.OWNER: '~',
        ];


import std.traits : OriginalType;
alias UserChannelFlagSet = OriginalType!UserChannelFlag;

struct GlobalUser
{
    string cased_name;
    byte ns_status = -1;
    ubyte auth_level = 50;
    ubyte ref_count = 1;
}

struct LocalUser
{
    GlobalUser* global_reference;
    UserChannelFlagSet user_channel_flags = UserChannelFlag.NONE;
}

struct Channel
{
    string cased_name;
    LocalUser[string] users;
}
