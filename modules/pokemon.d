// -*- flycheck-dmd-include-path: ("../"); -*-
import module_base;
extern (C) IRCModule m;

import std.algorithm : filter;


struct Pokemon
{
    struct BaseStats
    {
        int hp, atk, def, spa, spd, spe;
    }
    BaseStats baseStats;

    struct Abilities
    {
        string ability0 = null;
        string ability1 = null;
        string abilityH = null;

        this(in JSONValue json)
        {
            const JSONValue[string]* o = &json.object();
            if (auto p = "0" in *o)
            {
                ability0 = p.str();
            }
            if (auto p = "1" in *o)
            {
                ability1 = p.str();
            }
            if (auto p = "H" in *o)
            {
                abilityH = p.str();
            }
        }

        string opCast(T : string)()
        {
            string s = ability0 ? ability0 : "";
            s ~= (ability0 && ability1) ? "/" : "";
            s ~= ability1 ? ability1 : "";
            s ~= abilityH ? '/' ~ abilityH ~ " (H)" : "";
            return s;
        }
    }
    Abilities abilities;

    string species;
    string[] types;
    double weightkg;
    string tier;
}

int weight_to_lkgk(double weightkg)
{
    if (weightkg <= 10)
    {
        return 20;
    }
    else if (weightkg <= 25)
    {
        return 40;
    }
    else if (weightkg <= 50)
    {
        return 60;
    }
    else if (weightkg <= 100)
    {
        return 80;
    }
    else if (weightkg <= 200)
    {
        return 100;
    }
    else
    {
        return 120;
    }
}

// TODO: fill out
string[2][] form_names =
    [
        ["rotomh", "rotomheat"],
        ["rotomw", "rotomwash"],
        ["rotoms", "rotomfan"],
        ["rotomc", "rotommow"],
        ["rotomf", "rotomfrost"],
        ["deoxysn", "deoxys"],
        ["deoxysa", "deoxysattack"],
        ["deoxyss", "deoxysspeed"],
        ["deoxysd", "deoxysdefense"],
        ["landorust", "landorustherian"],
        ["thundurust", "thundurustherian"],
        ["tornadust", "tornadustherian"],
        ["hoopau", "hoopaunbound"],
        ];

// this is here to play nice with module_data
struct Pokedex
{
    Pokemon[string]* p;

    ref Pokemon[string] f()
    {
        return *p;
    }

    alias f this;
}
Pokedex pokedex;

// fsr not able to be put in module ctor
// returns true for success, false for failure
bool load_pokedex() nothrow
{
    try
    {
        pokedex = static_json!(Pokemon[string])(parseJSON(readText("./module_files/pokemon/pokedex.json")));
        foreach (ref ns; form_names)
        {
            enforce(ns[1] in pokedex);
            pokedex[ns[0]] = pokedex[ns[1]];
        }
        return true;
    }
    catch (Exception e)
    {
        try
        {
            writeln("load_pokedex exception: ", e.msg);
            return false;
        }
        catch
        {
            // this shouldn't ever really happen, but if it does, let's just halt
            assert(0);
        }
    }
}

static this()
{
    m.initialize = function void(ref Variant[string] module_data, bool first_time)
        {
            // obnoxious workaround
            auto p = pokedex.p;
            module_data.register_module_data!(p, Pokemon[string], "pokedex")();
            pokedex.p = p;

            bool res = load_pokedex();
            assert(res);
        };

    m.commands["pokemonreload"] = new Command(
        function void(Client c, string source, string channel, string message)
        {
            if (load_pokedex())
            {
                c.send_privmsg(channel, "Done reloading pokemon data.");
            }
            else
            {
                c.send_privmsg(channel, "Error reloading pokemon data.");
            }
        }, -1, UserChannelFlag.NONE, 200);

    m.commands["stats"] = new Command(
        function void(Client c, string source, string channel, string message)
        {
            if (message.length == 0)
            {
                c.send_privmsg(channel, "Usage - " ~ COMMAND_CHAR ~ "stats [pokemon]");
                return;
            }

            string pokemon_name = message.toLower();

            // TODO: put these in as keys when loading, or keep it here?
            if (pokemon_name.length >= 4 && pokemon_name[0..4] == "mega")
            {
                writeln("mega");
                int i;
                for (i = 5; i < pokemon_name.length && pokemon_name[i] != ' ' && pokemon_name[i] != '-'; i++) {}
                pokemon_name = pokemon_name[5..i] ~ "mega" ~ pokemon_name[i..$];
                writeln(pokemon_name);
            }

            pokemon_name = pokemon_name.filter!(a => a != ' ' && a != '-')().to!string();

            if (auto p = pokemon_name in pokedex)
            {
                c.send_privmsg(channel, p.species, " - ", p.types.join('/'), " | ",
                               cast(string)(p.abilities), " | ",
                               p.baseStats.hp.to!string(), "/",
                               p.baseStats.atk.to!string(), "/",
                               p.baseStats.def.to!string(), "/",
                               p.baseStats.spa.to!string(), "/",
                               p.baseStats.spd.to!string(), "/",
                               p.baseStats.spe.to!string(),
                               " | LK/GK: ", weight_to_lkgk(p.weightkg).to!string(), " | ",
                               p.tier
                    );
            }
            else
            {
                c.send_privmsg(channel, "Error - no such pokemon " ~ message ~ ".");
            }
        }, -1, UserChannelFlag.NONE, 50);
}
