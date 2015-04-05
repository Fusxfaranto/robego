import std.socket;

void send_raw(ref Socket s, in char[] line)
{
    assert(line.length < 510);
    assert(s.send(line ~ "\r\n") == line.length + 2);
}
