
import irc : Client;

debug import std.stdio;



void main()
{
    auto c = new Client("Robego", "Robego", "Robego", "irc.synirc.net", ["#fusxbottest"/*, "#program"*/]);

    c.run_loop();

    debug writeln("end of main");
    debug stdout.flush();
}



static ~this()
{
    debug writeln("main destructor");
    debug stdout.flush();
}



// TODO: idle action system
