# Tredjepartskode i vendor/ og fonts/

Alt ligger her for at undgå kald til CDN'er (GDPR + stabilitet). Opdatér bevidst – ikke automatisk.

| Pakke | Version | Licens |
|---|---|---|
| Leaflet | 1.9.4 | BSD-2-Clause |
| @supabase/supabase-js (UMD) | 2.118.0 | MIT |
| maplibre-gl | 5.24.0 | BSD-3-Clause (se vendor/maplibre/LICENSE-maplibre-gl.txt) |
| @maplibre/maplibre-gl-leaflet | 0.1.4 | ISC (se vendor/maplibre/LICENSE-maplibre-gl-leaflet.txt) |
| NoSleep.js | 0.12.0 | MIT |
| qrcodejs | 1.0.0 | MIT |
| Skrifttyper (Syne, Inter, Fredoka, Playfair Display, Special Elite) via Fontsource | 5.x | SIL Open Font License 1.1 |

Kortdata: © OpenStreetMap-bidragydere (ODbL). OpenFreeMap-fliser: © OpenMapTiles.
MapLibre 6.x leveres kun som ES-moduler (ingen script-fil) – derfor er v5 valgt, så der ikke skal bruges et build-trin.
