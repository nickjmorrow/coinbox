import fs from 'fs';
const {icon} = await import(process.env.HOME + '/.claude/skills/icon-design/references/glass.mjs');
const W='#fff', K='#000';
const gold=['#FFE07A','#FFB21E'];
const slotY=124, cut=slotY+6;
const box = {kind:'white', y:[108,212], mask:`<rect x="40" y="108" width="176" height="104" rx="30" fill="${W}"/><rect x="72" y="${slotY}" width="112" height="12" rx="6" fill="${K}"/>`};
const below = `<rect x="0" y="${cut}" width="256" height="256" fill="${K}"/>`;
const concepts = {
  small:  [{kind:'color', c:gold, y:[50,cut], mask:`<circle cx="128" cy="${cut-38}" r="40" fill="${W}"/>${below}`}],
  edge:   [{kind:'color', c:gold, y:[40,cut], mask:`<ellipse cx="128" cy="${cut-44}" rx="28" ry="48" fill="${W}"/>${below}`}],
  tilt:   [{kind:'color', c:gold, y:[40,cut], mask:`<ellipse cx="128" cy="${cut-44}" rx="30" ry="48" fill="${W}" transform="rotate(-14 128 ${cut})"/>${below}`}],
  stack:  [{kind:'color', c:gold, y:[44,cut], alpha:.6, mask:`<ellipse cx="146" cy="70" rx="24" ry="34" fill="${W}" transform="rotate(-14 146 70)"/>`, shadow:false},
           {kind:'color', c:gold, y:[60,cut], mask:`<ellipse cx="112" cy="${cut-40}" rx="26" ry="44" fill="${W}" transform="rotate(-14 112 ${cut})"/>${below}`}],
};
for (const [n, coin] of Object.entries(concepts)) for (const [t, tile] of Object.entries({green:['#5EE07A','#1FB447'], indigo:['#6366F1','#2E2A9E']}))
  fs.writeFileSync(`r2-${n}-${t}.svg`, icon({id:`cb-${n}-${t}`, name:'Coinbox', tile, layers:[box, ...coin]}, 'flat'));
