# AirVibes

Wind checker for kitesurfing, wing foiling, windsurfing and sailing.

- Opens on a map, finds you by GPS and shows live wind at named beaches within 50 km
- Each beach marker shows wind direction, speed and a Go / Marginal / No go colour against your limits
- Tap a beach for the full forecast: verdict, rideable daylight windows over 3 days, 48 hour chart
- Tap the compass in a beach's forecast to mark the directions that work there
- Measured wind from Bureau of Meteorology stations (square markers), next to the forecast for each beach
- Tide icon: water level and rising/falling arrow, with the next high and low (modelled, not official tide tables)

Data: wind and tide from [Open-Meteo](https://open-meteo.com), measured wind from the [Bureau of Meteorology](http://www.bom.gov.au) public FTP (refreshed every ~10 min by a GitHub Action into the `data` branch), beaches from [OpenStreetMap](https://www.openstreetmap.org) via the Overpass API, map tiles from OpenStreetMap. No API keys.

Live at https://wallyclewett.github.io/airvibes/ — on iPhone open in Safari, Share → Add to Home Screen.
