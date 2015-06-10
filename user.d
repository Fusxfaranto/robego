
enum channel_auth_t {NONE, VOICE, HOP, OP, ADMIN, OWNER}

enum channel_auth_t[char] auth_chars =
    ['+': channel_auth_t.VOICE,
     '%': channel_auth_t.HOP,
     '@': channel_auth_t.OP,
     '&': channel_auth_t.ADMIN,
     '~': channel_auth_t.OWNER];

struct GlobalUser
{
    string cased_name;
    ubyte auth_level = 0;
}

struct LocalUser
{
    GlobalUser* global_reference;
    channel_auth_t channel_auth_level = channel_auth_t.NONE;
    ubyte auth_level = 0;
}

struct Channel
{
    string cased_name;
    LocalUser[string] users;
}
