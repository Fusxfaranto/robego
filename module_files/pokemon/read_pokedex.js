var d = require('./pokedex.js');
var f = require('./formats-data.js')

dex = d.BattlePokedex;

for (var k in dex)
{
    if ('tier' in f.BattleFormatsData[k])
    {
        dex[k].tier = f.BattleFormatsData[k].tier;
    }
}

for (var k in dex)
{
    if (!('tier' in f.BattleFormatsData[k]))
    {
        dex[k].tier = f.BattleFormatsData[dex[k].baseSpecies.toLowerCase()].tier;
    }
}

console.log(JSON.stringify(d.BattlePokedex));
