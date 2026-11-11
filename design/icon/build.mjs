import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const coin = (cx, cy, r, cut) => [
  {kind:'color', c:['#FFE07A','#FFB21E'], y:[cy-r, cut], mask:`<circle cx="${cx}" cy="${cy}" r="${r}" fill="${W}"/><rect x="0" y="${cut}" width="256" height="256" fill="${K}"/>`},
  {kind:'color', c:['#FFC93C','#F59E0B'], y:[cy-r, cut], mask:`<circle cx="${cx}" cy="${cy}" r="${r-11}" fill="${W}"/><circle cx="${cx}" cy="${cy}" r="${r-19}" fill="${K}"/><rect x="0" y="${cut}" width="256" height="256" fill="${K}"/>`},
];
const box = (slot=true) => ({kind:'white', y:[110,212], mask:`<rect x="44" y="110" width="168" height="102" rx="30" fill="${W}"/>` + (slot ? `<rect x="74" y="126" width="108" height="16" rx="8" fill="${K}"/>` : '')});
const variants = {
  green:  ['#5EE07A','#1FB447'],
  indigo: ['#6366F1','#2E2A9E'],
  mint:   ['#45E0C8','#00A898'],
  blue:   ['#4CC9FF','#0A7FF5'],
};
for (const [name, tile] of Object.entries(variants)) {
  // box behind, coin in front, cut where it drops into the slot
  const spec = {id:'coinbox-'+name, name:'Coinbox', tile, layers:[box(), ...coin(128, 84, 46, 134)]};
  fs.writeFileSync(`r1-${name}.svg`, icon(spec, 'flat'));
}
