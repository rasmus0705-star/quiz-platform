// =====================================================================
// map-config.js – HER skifter du kortudbyder. Resten af systemet følger med.
//
//  provider:
//   'openfreemap' GRATIS, uden nøgle og uden registrering – og kommerciel brug er tilladt (ifølge udbyderen).
//                 Ingen driftsgaranti: deres vilkår siger, at tjenesten leveres som den er og kan ændres/lukke.
//                 Vektorkort via MapLibre (hentes kun når kortet vises). ANBEFALET så længe I vil holde det gratis.
//   'osm'         OpenStreetMaps egne servere. KUN til udvikling/test – kommerciel drift er "heavy use" og kan blokeres.
//   'maptiler'    MapTiler Cloud. Nøgle påkrævet. Gratis plan = kun ikke-kommerciel brug; betalt ca. 25 USD/md. (tjek selv).
//   'stadia'      Stadia Maps. Nøgle ELLER domæne-godkendelse. Gratis plan = kun ikke-kommerciel; betalt fra ca. 20 USD/md.
//   'custom'      Egen tile-server – udfyld 'custom' nedenfor.
//
//  NÅR I VOKSER: skift provider til 'maptiler' eller 'stadia', sæt key – færdig. Intet andet i koden skal ændres.
//
//  key: API-nøglen (kun maptiler/stadia). Den er synlig i browseren, så BEGRÆNS den til jeres domæne i udbyderens dashboard.
//
//  Hvis kortet ser forkert ud på en telefon: sæt provider:'osm' (test) og skriv hvad du ser.
// =====================================================================
const MAP_CONFIG = {
  provider: 'openfreemap',
  key: '',

  // Kun til provider:'custom'. {z}/{x}/{y}/{r}/{style} erstattes automatisk.
  custom: {
    url: '',                // fx https://tiles.example.dk/{style}/{z}/{x}/{y}.png
    attribution: '',        // fx © Jeres kortudbyder © OpenStreetMap-bidragydere
    geocodeUrl: '',         // valgfri, fx https://geo.example.dk/search?q={q}  (GeoJSON eller Nominatim-format)
    styles: {}              // valgfri, fx { dark:'nat', light:'dag' }
  },

  // Stilnavne pr. udbyder. Ret dem her, hvis en udbyder omdøber en stil.
  // En stil der ikke findes her bruger udbyderens 'light' + et farvefilter i browseren.
  styles: {
    // 'bright' har tydelige veje (liberty er cremefarvet med hvide veje – svært at læse udendørs). Er 'bright' stadig svær at læse, så prøv 'positron' her.
    // 'dark' er ikke officielt reklameret – falder automatisk tilbage til liberty + mørkt filter.
    openfreemap: { light: 'bright', outdoor: 'liberty', dark: 'dark' },
    maptiler:    { light: 'streets-v2', dark: 'dataviz-dark', outdoor: 'outdoor-v2', winter: 'winter-v2' },
    stadia:      { light: 'alidade_smooth', dark: 'alidade_smooth_dark', outdoor: 'outdoors', watercolor: 'stamen_watercolor' }
  }
}
