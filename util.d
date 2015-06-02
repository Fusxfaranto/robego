

import std.stdio : writeln;
import std.string : stripRight;
import std.functional : binaryFun;


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
