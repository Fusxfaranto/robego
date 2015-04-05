all: main.d
	gdc main.d util.d irc_commands.d -o main  

run:
	./main

clean:
	$(RM) main
