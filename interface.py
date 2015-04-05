import socket


s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.setblocking(0);

s.connect("./sock")


s.shutdown()
s.close()


