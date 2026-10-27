// =====================================================================
// map.js – kortlag + adressesøgning, uafhængigt af udbyder (se map-config.js).
// Kræver Leaflet (L) i siden. Alle funktioner starter med 'jagten' for ikke at støde ind i sidernes egne navne.
// Udbydere: openfreemap (gratis, vektor via MapLibre) · osm (kun test) · maptiler · stadia · custom
// =====================================================================

// Farvefiltre der gør ét lyst kort til et mørkt/vinter/sepia-kort, når udbyderen ikke har stilen selv.
const JAGTEN_MAP_FILTERS = {
  light: '',
  dark: 'invert(1) hue-rotate(180deg) brightness(1.15) contrast(1.15) saturate(.8)',     // lysere end før: veje og navne skal kunne ses
  winter: 'saturate(.8) brightness(1.05) contrast(1.12) hue-rotate(185deg)',
  outdoor: 'saturate(1.2) contrast(1.02)',
  watercolor: 'saturate(.95) contrast(1.06) brightness(1.02) sepia(.15)'
}

const JAGTEN_OSM_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
const JAGTEN_OFM_STYLES = 'https://tiles.openfreemap.org/styles/'
const JAGTEN_OFM_STABLE = 'liberty'          // den officielle, afprøvede stil – bruges som reserve, hvis ønsket stil ikke kan hentes
let   JAGTEN_GL_TIMEOUT_MS = 12000          // vektorkort der ikke er klar efter så lang tid → reserve

// Her ligger map.js → find rod-mappen, så MapLibre kan hentes fra vendor/ uanset hvilken side der kalder
const JAGTEN_BASE = (() => { try { return new URL('../', document.currentScript.src).href } catch (_) { return '' } })()

function jagtenMapCfg() {
  return (typeof MAP_CONFIG !== 'undefined' && MAP_CONFIG) ? MAP_CONFIG : { provider: 'osm', key: '', custom: {}, styles: {} }
}

// Den udbyder der FAKTISK bruges (en manglende nøgle falder tilbage, så siden aldrig står uden kort)
function jagtenProvider() {
  const c = jagtenMapCfg(), p = c.provider || 'osm'
  if (p === 'maptiler' && !c.key) { console.warn('[kort] provider=maptiler men ingen key – bruger OpenFreeMap'); return 'openfreemap' }
  if (p === 'custom' && !(c.custom && c.custom.url)) { console.warn('[kort] provider=custom men ingen url – bruger OpenFreeMap'); return 'openfreemap' }
  return ['openfreemap', 'osm', 'maptiler', 'stadia', 'custom'].includes(p) ? p : 'openfreemap'
}

function jagtenTileSpec(style) {
  const c = jagtenMapCfg(), p = jagtenProvider()
  const styles = (c.styles && c.styles[p]) || {}
  const enc = encodeURIComponent

  if (p === 'openfreemap') {
    const id = styles[style], sid = id || styles.light || 'liberty'
    return { provider: p, vector: true, native: !!id, styleName: sid, maxZoom: 19,
             attribution: 'OpenFreeMap © OpenMapTiles · Data fra OpenStreetMap',
             url: JAGTEN_OFM_STYLES + sid }                        // style-JSON, ikke en tile-skabelon
  }
  if (p === 'maptiler') {
    const id = styles[style], sid = id || styles.light || 'streets-v2'
    return { provider: p, native: !!id, maxZoom: 20, attribution: '© MapTiler © OpenStreetMap-bidragydere',
             url: `https://api.maptiler.com/maps/${sid}/256/{z}/{x}/{y}.png?key=${enc(c.key)}` }
  }
  if (p === 'stadia') {
    const id = styles[style], sid = id || styles.light || 'alidade_smooth'
    const jpg = sid === 'stamen_watercolor'                          // Watercolor findes kun som JPEG uden @2x
    const key = c.key ? `?api_key=${enc(c.key)}` : ''
    return { provider: p, native: !!id, maxZoom: jpg ? 16 : 20,
             attribution: sid.startsWith('stamen') ? '© Stadia Maps © Stamen Design © OpenStreetMap-bidragydere' : '© Stadia Maps © OpenMapTiles © OpenStreetMap-bidragydere',
             url: `https://tiles.stadiamaps.com/tiles/${sid}/{z}/{x}/{y}${jpg ? '' : '{r}'}.${jpg ? 'jpg' : 'png'}${key}` }
  }
  if (p === 'custom') {
    const cu = c.custom || {}, sid = (cu.styles && cu.styles[style]) || style
    return { provider: p, native: !!(cu.styles && cu.styles[style]), maxZoom: 19,
             attribution: cu.attribution || '© OpenStreetMap-bidragydere', url: cu.url.replace('{style}', sid) }
  }
  return { provider: 'osm', native: false, maxZoom: 19, attribution: '© OpenStreetMap-bidragydere', url: JAGTEN_OSM_URL }
}

function jagtenTileFilter(spec, style, tint) {
  return [spec.native ? '' : (JAGTEN_MAP_FILTERS[style] || ''), tint || ''].filter(Boolean).join(' ')
}

// ── MapLibre (til vektorkort) hentes først, når det er nødvendigt ──
function jagtenHasWebGL() {
  try { const c = document.createElement('canvas'); return !!(c.getContext('webgl2') || c.getContext('webgl')) } catch (_) { return false }
}
function jagtenLoadScript(url) {
  return new Promise((res, rej) => {
    const el = document.createElement('script')
    el.src = url; el.onload = () => res(); el.onerror = () => rej(new Error('Kunne ikke hente ' + url))
    document.head.appendChild(el)
  })
}
function jagtenLoadCss(url) {
  const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = url; document.head.appendChild(l)
}
let _jagtenGl = null
function jagtenLoadMapLibre(L) {
  if (_jagtenGl) return _jagtenGl
  _jagtenGl = (async () => {
    if (!jagtenHasWebGL()) throw new Error('WebGL findes ikke i denne browser')
    jagtenLoadCss(JAGTEN_BASE + 'vendor/maplibre/maplibre-gl.css')
    await jagtenLoadScript(JAGTEN_BASE + 'vendor/maplibre/maplibre-gl.js')
    await jagtenLoadScript(JAGTEN_BASE + 'vendor/maplibre/leaflet-maplibre-gl.js')   // skal komme efter Leaflet + MapLibre
    if (!L.maplibreGL) throw new Error('MapLibre-broen blev ikke indlæst')
  })()
  _jagtenGl.catch(() => { _jagtenGl = null })           // tillad nyt forsøg senere
  return _jagtenGl
}

function jagtenSetPaneFilter(map, f) {
  const p = map.getPane ? map.getPane('tilePane') : null
  if (p && p.style) p.style.filter = f
}

// Sidste udvej: OSM-fliser (til test; bør næsten aldrig ses i drift)
function jagtenOsmFallback(L, map, style, tint, why) {
  console.warn('[kort] ' + why + ' – bruger OSM midlertidigt')
  const layer = L.tileLayer(JAGTEN_OSM_URL, { maxZoom: 19, attribution: '© OpenStreetMap-bidragydere' }).addTo(map)
  jagtenSetPaneFilter(map, [JAGTEN_MAP_FILTERS[style] || '', tint || ''].filter(Boolean).join(' '))
  return layer
}

// Vent til kortets container har en størrelse. Et kort på en skjult fane (fx editorens "Poster") er 0 px stort, og et vektorkort
// oprettet dér bliver aldrig tegnet. Leaflet melder 'resize', når fanen vises (invalidateSize); en lille poll er ekstra sikkerhed.
function jagtenWhenSized(map) {
  return new Promise(resolve => {
    const sized = () => { try { const z = map.getSize(); return z.x > 0 && z.y > 0 } catch (_) { return true } }
    if (typeof map.getSize !== 'function' || sized()) return resolve()
    let done = false, timer = null
    const fin = () => { if (done) return; done = true; clearInterval(timer); try { map.off && map.off('resize', fin) } catch (_) {}; resolve() }
    try { map.on && map.on('resize', fin) } catch (_) {}
    timer = setInterval(() => { try { map.invalidateSize && map.invalidateSize({ animate: false }) } catch (_) {}; if (sized()) fin() }, 400)
  })
}

// Vektorkort via MapLibre inde i Leaflet. Reserve-kæde: ønsket stil → stabil lys stil + farvefilter → OSM-fliser.
function jagtenAddVector(L, map, spec, style, tint) {
  const out = { layer: null, spec, pending: null }
  const stable = JAGTEN_OFM_STABLE
  let done = false

  const toOsm = why => { done = true; out.layer = jagtenOsmFallback(L, map, style, tint, why) }

  const addGl = (styleName, native) => {
    // Lettere rendering på telefoner: ingen fade-animation, højst 2x pixeltæthed, ingen gentagelse af verden
    const layer = L.maplibreGL({ style: JAGTEN_OFM_STYLES + styleName, fadeDuration: 0, pixelRatio: Math.min(window.devicePixelRatio || 1, 2),
      refreshExpiredTiles: false, renderWorldCopies: false, updateInterval: 48 }).addTo(map)
    out.layer = layer
    const box = layer.getContainer && layer.getContainer()
    if (box && box.style) box.style.filter = jagtenTileFilter({ native }, style, tint)
    let ok = false, failed = false, errs = 0
    const failover = () => {
      if (ok || failed || done) return
      failed = true
      try { map.removeLayer(layer) } catch (_) {}
      if (styleName !== stable) addGl(stable, false)                  // fx 'dark'/'bright' kan ikke hentes → stabil stil + farvefilter
      else toOsm('OpenFreeMap leverer ikke kort')
    }
    const gl = layer.getMaplibreMap && layer.getMaplibreMap()
    if (gl && gl.on) {
      gl.on('load', () => { ok = true })
      gl.on('error', () => { if (!ok && ++errs >= 3) failover() })
    }
    setTimeout(failover, JAGTEN_GL_TIMEOUT_MS)
  }

  // Enhver fejl (script kan ikke hentes, WebGL, 0-størrelse …) giver OSM-fliser – aldrig et tomt, gråt kort
  out.pending = jagtenLoadMapLibre(L)
    .then(() => jagtenWhenSized(map))
    .then(() => addGl(spec.styleName, spec.native))
    .catch(err => toOsm(String(err && err.message || err)))
  return out
}

// Tilføjer kortlag + filter. Raster: hvis udbyderen ikke leverer en eneste tile (forkert nøgle, spærret) skiftes til OSM.
function jagtenAddTiles(L, map, style, tint) {
  const spec = jagtenTileSpec(style)
  if (spec.vector) return jagtenAddVector(L, map, spec, style, tint)

  let layer = L.tileLayer(spec.url, { maxZoom: spec.maxZoom, attribution: spec.attribution }).addTo(map)
  jagtenSetPaneFilter(map, jagtenTileFilter(spec, style, tint))

  let loads = 0, errors = 0, fell = false
  layer.on('tileload', () => { loads++ })
  layer.on('tileerror', () => {
    errors++
    if (fell || loads > 0 || errors < 6 || spec.provider === 'osm') return
    fell = true
    map.removeLayer(layer)
    layer = jagtenOsmFallback(L, map, style, tint, spec.provider + ' leverer ingen tiles (nøgle/vilkår?)')
  })
  return { layer, spec }
}

// Ren tekst til "Kort: …" under velkomstskærmen m.m. (må ikke vise HTML fra udbyderen)
function jagtenAttributionText() {
  return 'Kort: ' + jagtenTileSpec('light').attribution
}

// Besked til admin om kortets status
function jagtenMapNotice() {
  const p = jagtenProvider()
  if (p === 'osm') return '⚠️ Test-kort (OpenStreetMaps gratis servere). Skift udbyder i js/map-config.js, før I bruger løbene kommercielt.'
  if (p === 'openfreemap') return 'ℹ️ Gratis kort (OpenFreeMap) uden driftsgaranti. Skift til en betalt udbyder i js/map-config.js, når I vokser.'
  return ''
}

// ── Adressesøgning ──────────────────────────────────────────────────
// 'autocomplete' = må søge mens man skriver. 'submit' = kun når brugeren trykker søg (Nominatims regler forbyder autocomplete).
function jagtenGeocodeMode() {
  const p = jagtenProvider(), cu = jagtenMapCfg().custom || {}
  if (p === 'maptiler' || p === 'stadia') return 'autocomplete'
  if (p === 'custom' && cu.geocodeUrl) return 'autocomplete'
  return 'submit'
}

async function jagtenGeocode(query) {
  const q = String(query || '').trim()
  if (q.length < 2) return []
  const c = jagtenMapCfg(), p = jagtenProvider(), enc = encodeURIComponent
  let url

  if (p === 'maptiler')      url = `https://api.maptiler.com/geocoding/${enc(q)}.json?key=${enc(c.key)}&country=dk&language=da&limit=6`
  else if (p === 'stadia')   url = `https://api.stadiamaps.com/geocoding/v1/autocomplete?text=${enc(q)}&boundary.country=DK&size=6${c.key ? '&api_key=' + enc(c.key) : ''}`
  else if (p === 'custom' && c.custom && c.custom.geocodeUrl) url = c.custom.geocodeUrl.replace('{q}', enc(q))
  else                       url = `https://nominatim.openstreetmap.org/search?q=${enc(q)}&countrycodes=dk&format=json&limit=6&accept-language=da`

  const res = await fetch(url, { headers: { Accept: 'application/json' } })
  if (!res.ok) throw new Error('Søgningen fejlede (' + res.status + ')')
  const data = await res.json()

  if (Array.isArray(data)) {                                    // Nominatim-format
    return data.map(r => ({ label: r.display_name, lat: Number(r.lat), lng: Number(r.lon) })).filter(r => isFinite(r.lat) && isFinite(r.lng))
  }
  return (data.features || []).map(f => {                       // GeoJSON (MapTiler: center=[lon,lat]; Pelias/Stadia: geometry.coordinates)
    const ll = f.center || (f.geometry && f.geometry.coordinates)
    return { label: f.place_name || (f.properties && (f.properties.label || f.properties.name)) || f.text || '', lat: ll && ll[1], lng: ll && ll[0] }
  }).filter(r => r.label && isFinite(r.lat) && isFinite(r.lng))
}
