

import std.string : stripRight;

@safe:

pure const(inout(char[])[2]) split1(inout char[] s, in char delim)
{
    foreach (ulong i, char c; s)
    {
        if (c == delim)
        {
            return [stripRight(s[0..i]), s[(i + 1)..$]];
        }
    }
    debug writeln("<2> no colon??");
    return ["", s];
}
