
import irc : Client;

debug import std.stdio;



void main()
{
    auto c = new Client();

    c.run_loop();

    debug writeln("end of main");
    debug stdout.flush();
}



static ~this()
{
    debug writeln("main destructor");
    debug stdout.flush();
}
