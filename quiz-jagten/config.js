// Indstillinger. Udskift kun denne fil, så mister du ikke dine nøgler, når app.js opdateres.
window.QUIZ_CONFIG = {
  APP_NAVN: "Quizjagten",

  // true = vis også spørgsmål med status "kladde" (praktisk mens du tester)
  VIS_KLADDER: false,

  // Supabase bruges til live-spil, statistik og fejlmeldinger. Lad stå tomt, så kører appen uden.
  // Brug anon-nøglen eller publishable key (sb_publishable_...) – ALDRIG service_role/secret.
  SUPABASE_URL: "https://qmdqzdatlanyhewjwpzc.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_NHtkIMzpXk02rZA31usaPQ_mmHoAa0q",

  // false = send ikke svar-statistik til Supabase
  LOG_SVAR: true,

  // Sekunder pr. spørgsmål i live-spil (kan ændres i opsætningen)
  LIVE_SEKUNDER: 20
};
