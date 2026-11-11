import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const rnd=(w)=>`stroke="#fff" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const gold=['#FFE08A','#E3A020'];
// frame arc from (64,112) over (128,84) to (192,112); body hangs from it and flares to a near-flat base
const body = `<path d="M64 112 Q128 84 192 112 C 214 132, 222 168, 218 192 C 214 210, 200 216, 180 216 L 76 216 C 56 216, 42 210, 38 192 C 34 168, 42 132, 64 112 Z" fill="${W}" ${rnd(6)}/>`;
const band = `<path d="M64 112 Q128 84 192 112 C 198 118, 202 126, 205 134 Q128 108 51 134 C 54 126, 58 118, 64 112 Z" fill="${W}" ${rnd(4)}/>`;
const frame = `<path d="M62 113 Q128 82 194 113" fill="none" ${rnd(15)}/><circle cx="62" cy="114" r="11" fill="${W}"/><circle cx="194" cy="114" r="11" fill="${W}"/>`;
const clasp = `<circle cx="115" cy="80" r="14" fill="${W}"/><circle cx="141" cy="80" r="14" fill="${W}"/>`;
const goldLayer = {kind:'color', c:gold, y:[64,126], mask: frame + clasp};
const out = {
  parchment: {tile:['#FFF8EC','#EFDDBD'], light:true, layers:[
    {kind:'color', c:['#C98450','#8A4A1E'], y:[90,216], mask:body},
    {kind:'color', c:['#9A5626','#7A3F17'], y:[90,136], mask:band, shadow:false}, goldLayer]},
  oxblood:   {tile:['#C2414A','#7E1A24'], layers:[{kind:'white', y:[90,216], mask:body}, goldLayer]},
  green:     {tile:['#3FA56C','#17603A'], layers:[{kind:'white', y:[90,216], mask:body}, goldLayer]},
  graphite:  {tile:['#3C3C42','#18181B'], layers:[
    {kind:'color', c:['#C98450','#8A4A1E'], y:[90,216], mask:body},
    {kind:'color', c:['#9A5626','#7A3F17'], y:[90,136], mask:band, shadow:false}, goldLayer]},
};
for (const [n, v] of Object.entries(out))
  fs.writeFileSync(`r5-${n}.svg`, icon({id:`purse5-${n}`, name:'Coinbox', tile:v.tile, lightTile:!!v.light, layers:v.layers}, 'flat'));
