
import irc : Client;

debug import std.stdio;



void main()
{
    auto c = new Client("config.json");

    c.run_loop();

    c.destroy();

    debug writeln("end of main");
    debug stdout.flush();
}



static ~this()
{
    debug writeln("main destructor");
    debug stdout.flush();
}


// TODO: config reloading
// TODO: idle action system
// TODO: constants file
// TODO: remove uds system if i haven't decided to actually make it useful by release time
// TODO: one day, investigate closing segfault, i think it's a D issue
