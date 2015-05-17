import socket; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.connect("./sock")


s.shutdown()
s.close()


