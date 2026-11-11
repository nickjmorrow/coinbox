import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const slotY=126, cut=slotY+6, r=44, cy=cut-34;
const box = {kind:'white', y:[110,214], mask:`<rect x="38" y="110" width="180" height="104" rx="30" fill="${W}"/><rect x="70" y="${slotY}" width="116" height="12" rx="6" fill="${K}"/>`};
const below = `<rect x="0" y="${cut}" width="256" height="256" fill="${K}"/>`;
const coin = [
  {kind:'color', c:['#FFE27A','#FFB21E'], y:[cy-r,cut], mask:`<circle cx="128" cy="${cy}" r="${r}" fill="${W}"/>${below}`},
  {kind:'color', c:['#F7B731','#E8930C'], y:[cy-r,cut], mask:`<circle cx="128" cy="${cy}" r="${r-11}" fill="${W}"/><circle cx="128" cy="${cy}" r="${r-18}" fill="${K}"/>${below}`},
];
const tiles = {green:['#5EE07A','#1FB447'], mint:['#45E0C8','#00A898'], blue:['#4CC9FF','#0A7FF5'], graphite:['#3C3C42','#18181B']};
for (const [t, tile] of Object.entries(tiles))
  fs.writeFileSync(`r3-${t}.svg`, icon({id:`cb3-${t}`, name:'Coinbox', tile, layers:[box, ...coin]}, 'flat'));
