

import std.stdio : writeln;
import std.string : stripRight;


const(inout(char[])[2]) split1(inout char[] s, in char delim) pure @safe
{
    foreach (ulong i, char c; s)
    {
        if (c == delim)
        {
            return [stripRight(s[0..i]), s[(i + 1)..$]];
        }
    }
    //debug writeln("no delim");
    return ["", s];
}


/*T[S] aa_merge(T, S)(in T[S] a, in T[S] b, T function(T, T) pure callback) pure
{
    T[S] c = a.dup();
    foreach (S s, T t; b)
    {
        auto p = s in c;
        if (p is null)
            c[s] = t;
        else
            *p = callback(*p, t);
    }
    return c;
}*/

void aa_merge_inplace(T, S)(ref T[S] a, in T[S] b, T function(T, T) pure callback) pure
{
    foreach (S s, T t; b)
    {
        auto p = s in a;
        if (p is null)
            a[s] = t;
        else
            *p = callback(*p, t);
    }
}

void aa_merge_inplace(T, U, S)(ref T[S] a, in U[S] b, T function(T, U) pure callback, T sent) pure
{
    foreach (S s, U u; b)
    {
        auto p = s in a;
        if (p is null)
            a[s] = callback(sent, u);
        else
            *p = callback(*p, u);
    }
}
