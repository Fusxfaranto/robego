
import core.time : MonoTime, Duration, dur;

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


struct TemporaryListener
{
    bool delegate(in char[] source, in char[] command, in char[][] args, in char[] message) action;
}
