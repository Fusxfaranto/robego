

import std.stdio : writeln;
import std.string : stripRight, replace;
import std.functional : binaryFun;
import std.algorithm : map;
import std.array : array;
import std.traits : isInstanceOf, FieldNameTuple, isPointer, isAssociativeArray,
    ValueType, KeyType, isCallable /*, hasMember*/;
import std.typetuple : allSatisfy;
import std.conv : to;
import std.json : JSONValue, JSON_TYPE, JSONException;
import std.exception : enforce;


// this is for use as a default lazy void parameter
void noop() {}

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

const(inout(char)[]) get_nick(inout char[] s) pure nothrow @safe
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

// TODO: replace with a PQ lol...
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


// this can't be inout.  i don't know why.  file a bug report?
const(char[]) escape_code_as_string(const char[] code)
{
    return code
        .replace("\\", "\\\\")
        .replace("\?", "\\\?")
        .replace("\'", "\\\'")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t");
}


T static_json(T)(auto ref in JSONValue json)
{
    // json constructor
    static if (__traits(compiles, T(json)))
    {
        return T(json);
    }
    else static if (is(T == bool))
    {
        enforce(json.type() == JSON_TYPE.TRUE || json.type() == JSON_TYPE.FALSE);
        return json.type() == JSON_TYPE.TRUE;
    }
    else static if (__traits(isIntegral, T))
    {
        return to!T(json.integer());
    }
    else static if (__traits(isFloating, T))
    {
        if (json.type() == JSON_TYPE.INTEGER)
        {
            return to!T(json.integer());
        }
        return to!T(json.floating());
    }
    else static if (is(T == string))
    {
        return json.str();
    }
    else static if (is(T : U[], U))
    {
        return array(json.array().map!(x => static_json!U(x))());
    }
    else static if (is(T : V[string], V))
    {
        T t;
        foreach (string k, JSONValue v; json.object())
        {
            t[k] = static_json!V(v);
        }
        return t;
    }
    else static if (__traits(isPOD, T))
    {
        T t;
        if (json.type() == JSON_TYPE.OBJECT)
        {
            foreach (field_name; FieldNameTuple!T)
            {
                alias U = typeof(__traits(getMember, t, field_name));
                __traits(getMember, t, field_name) = static_json!U(json.object[field_name]);
            }
        }
        else if (json.type() == JSON_TYPE.ARRAY)
        {
            foreach (int i, field_name; FieldNameTuple!T)
            {
                alias U = typeof(__traits(getMember, t, field_name));
                __traits(getMember, t, field_name) = static_json!U(json.array[i]);
            }
        }
        else
        {
            throw new JSONException("not object or array");
        }
        return t;
    }
    else
    {
        static assert(0);
    }
}


T aa_diff(alias f, T : U[V], U, V)(T a, T b) if
    (is(typeof(binaryFun!f(ValueType!T.init, ValueType!T.init)) == bool))
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

V* get_create(K, V)(ref V[K] aa, string key, lazy V value = V.init)
{
    auto p = key in aa;
    if (p)
    {
        return p;
    }
    return &(aa[key] = value());
}
V* assign_create(K, V)(ref V[K] aa, string key, lazy V value = V.init)
{
    auto p = key in aa;
    if (p)
    {
        *p = value;
        return p;
    }
    return &(aa[key] = value());
}

T idup_elems(T : U[], U)(T a)
{
    T o = new T(a.length);
    foreach(i, e; a)
    {
        o[i] = e.idup;
    }
    return o;
}

template Tuple(T...)
{
    alias Tuple = T;
}

template InTuple(alias Element)
{
    enum bool InTuple = false;
}

template InTuple(alias Element, alias T)
{
    enum bool InTuple = T == Element;
}

template InTuple(alias Element, alias T, Ts...)
{
    enum bool InTuple = T == Element || InTuple!(Element, Ts);
}

template StaticMap(alias Template, alias T)
{
    alias StaticMap = Template!T;
}

template StaticMap(alias Template, alias T, Ts...)
{
    alias StaticMap = Tuple!(Template!T, StaticMap!(Template, Ts));
}

template KWArg(string Keyword_, alias Arg_)
{
    alias Keyword = Keyword_;
    alias Arg = Arg_;
}

void struct_init(T, KWArgs...)(ref T s) if (__traits(isPOD, T))
{
    alias Fields = FieldNameTuple!T;
    template GetKeyword(alias K) {alias GetKeyword = K.Keyword;}
    alias Keywords = StaticMap!(GetKeyword, KWArgs);
    foreach (F; Fields)
    {
        static assert(InTuple!(F, Keywords), "missing field in kwargs");
    }
    foreach (K; KWArgs)
    {
        //static assert(isInstanceOf!(KWArg, K));
        static assert(InTuple!(K.Keyword, Fields), "kwarg is not a field");
        __traits(getMember, s, K.Keyword) = K.Arg;
    }
}
