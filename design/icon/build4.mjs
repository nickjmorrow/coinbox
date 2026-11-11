import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const rnd=(w)=>`stroke="#fff" stroke-width="${w}" stroke-linejoin="round" stroke-linecap="round"`;
const gold=['#FFE08A','#E9A825'];
// pouch: narrow at the frame, bulging below, round bottom
const pouch = `<path d="M70 108 C 34 128, 34 214, 128 214 C 222 214, 222 128, 186 108 Z" fill="${W}" ${rnd(8)}/>`;
const frame = `<path d="M66 110 Q128 76 190 110" fill="none" ${rnd(16)}/><circle cx="66" cy="110" r="11" fill="${W}"/><circle cx="190" cy="110" r="11" fill="${W}"/>`;
const clasp = `<circle cx="116" cy="76" r="13" fill="${W}"/><circle cx="140" cy="76" r="13" fill="${W}"/>`;
const goldLayer = {kind:'color', c:gold, y:[62,122], mask: frame + clasp};
const variants = {
  parchment: {tile:['#FFF8EC','#F0E0C2'], light:true, body:{kind:'color', c:['#C9824A','#8C4B1F'], y:[100,216], mask:pouch}},
  oxblood:   {tile:['#C2414A','#7E1A24'], body:{kind:'white', y:[100,216], mask:pouch}},
  green:     {tile:['#3FA56C','#17603A'], body:{kind:'white', y:[100,216], mask:pouch}},
  leather:   {tile:['#C07A45','#7A4420'], body:{kind:'color', c:['#FFF6E4','#F2DDB8'], y:[100,216], mask:pouch}},
};
for (const [n, v] of Object.entries(variants))
  fs.writeFileSync(`r4-${n}.svg`, icon({id:`purse-${n}`, name:'Coinbox', tile:v.tile, lightTile:!!v.light, layers:[v.body, goldLayer]}, 'flat'));
