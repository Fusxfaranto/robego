
import core.time : MonoTime, Duration, dur;
import module_base : Listener;

class DelayedAction
{
    public:
        MonoTime time;

        this(MonoTime t = MonoTime.min())
        {
            time = t;
        }

        this(Duration d)
        {
            time = MonoTime.currTime() + d;
        }

        this(long n)
        {
            this(dur!"msecs"(n));
        }
}


class DelayedQuit : DelayedAction {}

class DelayedReload : DelayedAction {}

class DelayedCallback : DelayedAction
{
    public:
        void delegate() cb;

        this(void delegate() c)
        {
            super();
            cb = c;
        }

        this(T)(void delegate() c, T t)
        {
            super(t);
            cb = c;
        }
}


enum TLOption : ubyte {QUEUE, DONE, RUN_THIS, RUN_DONE}

struct TemporaryListener
{
    TLOption delegate(in char[] source, in char[] command, in char[][] args, in char[] message) action = null;
}

struct TLWaitingAction
{
    Listener* f;
    const(char)[] source;
    const(char)[][] args;
    const(char)[] message;
}
