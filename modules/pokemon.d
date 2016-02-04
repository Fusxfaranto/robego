// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;


struct Pokemon
{
    struct BaseStats
    {
        int hp, atk, def, spa, spd, spe;
    }
    BaseStats baseStats;

    string species;
    string[] types;
}

Pokemon[string] pokedex;

// fsr not able to be put in module ctor
void load_pokedex()
{
    pokedex = static_json!(Pokemon[string])(parseJSON(readText("./module_files/pokemon/pokedex.json")));
}

static this()
{
    load_pokedex();

    m.commands["pokemonreload"] = new Command(
        function void(Client c, string source, string channel, string message)
        {
            load_pokedex();
            c.send_privmsg(channel, "Done reloading pokemon data.");
        }, -1, UserChannelFlag.NONE, 50);

    m.commands["stats"] = new Command(
        function void(Client c, string source, string channel, string message)
        {
            if (message.length == 0)
            {
                c.send_privmsg(channel, "Usage - " ~ COMMAND_CHAR ~ "stats [pokemon]");
                return;
            }

            string pokemon_name = message.toLower();

            if (auto p = pokemon_name in pokedex)
            {
                c.send_privmsg(channel, p.species, " - ", p.types.join('/'), " | ",
                               p.baseStats.hp.to!string(), "/",
                               p.baseStats.atk.to!string(), "/",
                               p.baseStats.def.to!string(), "/",
                               p.baseStats.spa.to!string(), "/",
                               p.baseStats.spd.to!string(), "/",
                               p.baseStats.spe.to!string());
            }
            else
            {
                c.send_privmsg(channel, "Error - no such pokemon " ~ message ~ ".");
            }
        }, -1, UserChannelFlag.NONE, 50);
}
