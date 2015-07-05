

import std.stdio : writeln;
import std.string : stripRight;
import std.functional : binaryFun;
import std.traits : isPointer, isAssociativeArray, ValueType, KeyType /*, hasMember*/;
import std.typetuple : TypeTuple;


const(inout(char)[][2]) splitN(int n : 1)(inout(char)[] s, in char delim) pure nothrow @safe
{
    foreach (i, c; s)
    {
        if (c == delim)
        {
            //return [stripRight(s[0..i]), s[(i + 1)..$]];
            return [s[0..i], s[(i + 1)..$]];
        }
    }
    //debug writeln("no delim");
    return [s, ""];
}

const(inout(char)[][n + 1]) splitN(int n)(inout(char)[] s, in char delim) pure nothrow if (n >= 1)
{
    size_t index = 0;
    size_t last_i1 = 0;
    inout(char)[][n + 1] o = void;
    for (size_t i = 0; i < s.length; i++)
    {
        if (s[i] == delim)
        {
            o[index++] = s[last_i1..i];
            last_i1 = i + 1;
            if (index == n) break;
        }
    }
    o[index++] = s[last_i1..$];
    while (index <= n)
        o[index++] = typeof(o[0]).init;
    return o;
}

alias split1 = splitN!1;

bool is_channel(in char[] s) pure nothrow @safe
{
    return s[0] == '#';
}

const(char[]) get_nick(in char[] s) pure nothrow @safe
{
    return split1(s, '!')[0];
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

void aa_merge_inplace(T, S)(ref T[S] a, ref T[S] b, T function(T, T) pure callback) pure
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

void aa_merge_inplace(T, U, S)(ref T[S] a, ref U[S] b, T function(T, U) pure callback, T sent) pure
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

class SortedList(T, alias f) if(is(typeof(binaryFun!f(T.init, T.init)) == bool))
{
private:
    struct node
    {
        node* next;
        T datum;
    }
    node* first = null;
    alias pred = binaryFun!f;

public:
    bool has_items()
    {
        return cast(bool)first;
    }

    T front()
    {
        assert(first);
        return first.datum;
    }

    void pop()
    {
        assert(first);
        first = first.next;
    }

    void insert(T elem)
    {
        if (first is null)
        {
            first = new node(null, elem);
        }
        else if (!pred(first.datum, elem))
        {
            first = new node(first, elem);
        }
        else
        {
            node* n = first;
            for (; n.next !is null && pred(n.next.datum, elem); n = n.next) {}
            n.next = new node(n.next, elem);
        }
    }
}

unittest
{
    import std.algorithm : sort;

    auto l = new SortedList!(int, (a, b) => a < b);
    int[] items = [5, 2, 9, 0, -1, 5];
    foreach(x; items)
    {
        l.insert(x);
    }

    foreach(x; sort!"a < b"(items))
    {
        assert(x == l.front);
        l.pop();
    }
}


T aa_diff(alias f, T : U[V], U, V)(T a, T b)
    if(is(typeof(binaryFun!f(ValueType!T.init, ValueType!T.init)) == bool))
{
    alias pred = binaryFun!f;
    T o;
    foreach (V key, U value; a)
    {
        if (auto p = key in b)
        {
            if (!pred(*p, value))
                o[key] = value;
        }
        else
            o[key] = value;
    }
    return o;
}

bool deep_compare(T)(T a, T b)
{
    // this ought to use hasMember!(T, "tupleof"),
    // but for some reason (compiler bug?) that's evaluating as false on structs
    static if (__traits(compiles, a.tupleof))
    {
        foreach(i, _; a.tupleof)
        {
            if (!deep_compare(a.tupleof[i], b.tupleof[i]))
            {
                return false;
            }
        }
        return true;
    }
    else
    {
        static if (isPointer!T)
        {
            return deep_compare(*a, *b);
        }
        else static if (isAssociativeArray!T)
        {
            return aa_diff!(deep_compare!(ValueType!T), T)(a, b).length == 0;
        }
        else
        {
            return a == b;
        }
    }
}
