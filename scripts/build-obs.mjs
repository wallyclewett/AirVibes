// Builds obs.json: latest wind at every Bureau of Meteorology station, from the BOM public FTP state files.
// Usage: node scripts/build-obs.mjs <dir with IDx60920.xml files> <out file>
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [dir, out] = process.argv.slice(2);
const attr = (s, name) => s.match(new RegExp(`\\b${name}="([^"]*)"`))?.[1];
const el = (s, type) => s.match(new RegExp(`<element[^>]*type="${type}"[^>]*>([^<]*)</element>`))?.[1];

const stations = [];
for (const f of readdirSync(dir).filter(f => /^ID[A-Z]60920\.xml$/.test(f))) {
  const xml = readFileSync(join(dir, f), "utf8");
  for (const m of xml.matchAll(/<station\b([^>]*)>([\s\S]*?)<\/station>/g)) {
    const [, head, body] = m;
    const period = body.match(/<period\b[^>]*index="0"[^>]*>[\s\S]*?<\/period>/)?.[0];
    if (!period) continue;
    const spd = el(period, "wind_spd"), dirTxt = el(period, "wind_dir");
    if (spd == null) continue;
    const deg = el(period, "wind_dir_deg");
    stations.push({
      id: attr(head, "bom-id"),
      name: attr(head, "description") || attr(head, "stn-name"),
      lat: +attr(head, "lat"), lon: +attr(head, "lon"),
      t: attr(period, "time-utc"),
      spd: +spd,
      gust: el(period, "wind_gust_spd") != null ? +el(period, "wind_gust_spd") : null,
      deg: deg != null ? +deg : null, // null when calm
      dir: dirTxt || null,
    });
  }
}
if (stations.length < 100) throw new Error(`Only ${stations.length} stations parsed, refusing to publish`);
writeFileSync(out, JSON.stringify({ source: "Bureau of Meteorology", updated: new Date().toISOString(), stations }));
console.log(`Wrote ${stations.length} stations`);
