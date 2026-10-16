// Builds beaches.json: every named beach in Australia from OpenStreetMap.
// Run by .github/workflows/beaches.yml (GitHub's runners can reach Overpass; browsers often get refused).
import { writeFileSync } from "node:fs";

const HOSTS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"];
const QUERY = `[out:json][timeout:600];
area["ISO3166-1"="AU"][admin_level=2]->.au;
nwr["natural"="beach"]["name"](area.au);
out center tags;`;

async function fetchBeaches() {
  for (const host of HOSTS) {
    try {
      const r = await fetch(host, { method: "POST", body: "data=" + encodeURIComponent(QUERY),
        headers: { "Content-Type": "application/x-www-form-urlencoded", "User-Agent": "AirVibes beach list builder (github.com/wallyclewett/airvibes)" } });
      if (!r.ok) throw new Error(host + " returned " + r.status);
      return (await r.json()).elements;
    } catch (e) { console.error(e.message); }
  }
  throw new Error("All Overpass hosts failed");
}

const km = (a, b) => {
  const r = Math.PI / 180, dLat = (b[1] - a[1]) * r, dLon = (b[2] - a[2]) * r;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * r) * Math.cos(b[1] * r) * Math.sin(dLon / 2) ** 2;
  return 12742 * Math.asin(Math.sqrt(h));
};

const els = await fetchBeaches();
const out = [];
for (const el of els) {
  const lat = el.lat ?? el.center?.lat, lon = el.lon ?? el.center?.lon;
  if (lat == null || !el.tags?.name) continue;
  const b = [el.tags.name.trim(), +lat.toFixed(4), +lon.toFixed(4)];
  // Long beaches are often mapped as several pieces with the same name; keep one per 3 km.
  if (out.some(o => o[0] === b[0] && km(o, b) < 3)) continue;
  out.push(b);
}
out.sort((a, b) => a[1] - b[1] || a[2] - b[2]);
if (out.length < 500) throw new Error(`Only ${out.length} beaches found, refusing to overwrite`);
writeFileSync("beaches.json", JSON.stringify({ source: "OpenStreetMap contributors (ODbL)", updated: new Date().toISOString().slice(0, 10), beaches: out }));
console.log(`Wrote ${out.length} beaches`);
