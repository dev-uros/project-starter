# Plan

Kuda ide project starter. Ništa od ovoga još nije napravljeno osim Laravel i
Vue dela; ovo je dogovoren pravac, ne specifikacija.

---

## Projekat je skup delova, ne tip

Projekat nije „backoffice" ili „sajt", nego skup aplikacija oko jednog API-ja.
Delovi se biraju po potrebi i dodaju i kasnije, u postojeći projekat — projekti
tako i rastu.

| deo | stack | folder | status |
| --- | --- | --- | --- |
| glavni API | Laravel | `api/` | ✅ postoji |
| backoffice | Vue SPA | `admin/` (danas `web/`) | ✅ postoji |
| interna aplikacija | Capacitor + Vue + Ionic + Nuxt UI | `app/` | sledeći — vidi dole |
| eksterna aplikacija | React Native | `mobile/` | izvući iz trenutnog projekta |
| javni sajt | Nuxt (ili Astro za čisto sadržajne) | `site/` | izvući iz trenutnog projekta |
| realtime | Fastify (WebSocket, SSE) | `realtime/` | kad zatreba |

U 90% slučajeva projekat je samo Laravel + Vue admin. Postoje i kombinacije bez
Laravela (npr. samo Fastify + Capacitor).

Novi template se pravi kad ga prvi projekat zatraži, po mogućstvu izvučen iz
tog projekta — ne svih osam unapred.

---

## Pravila između delova

- **Jedan API, jedna poslovna logika.** Svi klijenti gađaju Laravel. Nijedan
  drugi servis ne piše u istu bazu.
- **Rute po klijentu:** `/api/admin/...`, `/api/app/...`, `/api/mobile/v1/...`.
  Ispod su isti servisi i modeli; razlikuju se kontroleri i API Resources.
- **Auth:** Vue admin — Sanctum cookie sesija. Mobilne aplikacije — Sanctum
  tokeni, čuvani u secure storage-u, ne u `localStorage`.
- **Mobilne rute su verzionisane**, jer stara verzija aplikacije ostaje
  instalirana mesecima; uz to provera minimalne verzije koja traži update.
- **Fastify realtime je samo poštar:** Laravel objavi event u Redis, Fastify ga
  gurne povezanim klijentima. Ne dira bazu, nema poslovnu logiku. Za obična
  websocket obaveštenja prvo Laravel Reverb; Fastify kad treba SSE ili ozbiljno
  opterećenje (SSE u PHP-FPM-u drži po jedan worker po konekciji).
- **Portovi su fiksni po delu**, kao danas za API i Vite. Nuxt po defaultu traži
  3000, gde je već Grafana — sajt dobija svoj.

Laravel template treba od starta da bude spreman za ovo i kad postoji samo
admin: grupe ruta, token auth pored cookie autha, broadcast eventi preko Redisa.

---

## Capacitor interna aplikacija

Uzor je `~/Desktop/fg-projects/bullet-notes`: Ionic samo kao školjka, sav
vidljivi UI iz jedne biblioteke. Tamo je to roughness, ovde Nuxt UI.

### Ionic — samo školjka

- `IonApp`, `IonRouterOutlet`, `IonPage`, `IonContent`, `useIonRouter`
- `IonTabs` — tabovi koji pamte svoj stack (bullet-notes ih nema, ovde trebaju)
- `IonRefresher`, `IonInfiniteScroll` — vezani su za `IonContent` scroll, a
  liste sa API-ja ih traže
- `IonicVue` sa `mode: 'ios'` i `hardwareBackButton: false`
- prelazi po platformi: `mdTransitionAnimation` na Androidu, slide na iOS-u
- **treeshake pravilo u `vite.config.ts`** za `@ionic/core/components/ion-*` —
  bez njega se uvuče svih ~90 komponenti (oko megabajt)

Nijedna Ionic UI komponenta: bez Ionic toolbara, dugmadi, inputa ni overlay-a.

### Nuxt UI — sve vidljivo

Forme, dugmad, kartice, liste, modali, slideover-i, toast-ovi. Ionic CSS
varijable (`--ion-background-color`, `--ion-text-color`, `--ion-font-family`)
mapiraju se na boje Nuxt UI-ja, za light i dark.

Proveriti: Nuxt UI u običnom Vite projektu, bez Nuxta, sa `UApp` unutar
`IonApp`.

### Prenosi se iz bullet-notes

| fajl | šta radi |
| --- | --- |
| `src/composables/back.ts` | registar otvorenih slojeva: Android back zatvara najnoviji (`useBackClose`), pa stranicu nazad, pa minimizuje |
| `src/composables/keyboard.ts` | polje u fokusu ostaje iznad tastature |
| `src/composables/theme.ts` | light / dark / system, boja `SystemBars` |
| `capacitor.config.ts` | `SystemBars.insetsHandling: 'css'`, splash koji čeka stranicu |

Nuxt UI modal i slideover dobijaju tanak omotač koji zove `useBackClose` —
inače Android back zatvori ekran umesto modala.

### Novo u odnosu na bullet-notes

Bullet-notes je local-first (SQLite); interna aplikacija živi od API-ja:

- API klijent sa token authom, secure storage, obrada 401
- tabovi i liste sa refresh / infinite scroll
- push notifikacije iz Laravela

### Pre templatea

Probni projekat, oko dan posla, na pravom uređaju: tabovi sa stackovima, forma
u Nuxt UI-ju, Nuxt UI modal sa back dugmetom, dark mode, tastatura.

---

## Otvoreno

- Kako tačno izgleda setup ostalih delova (RN, sajt, realtime) — tek treba
  definisati.
- Preimenovanje `web/` u `admin/` u skripti i templateu.
- Kako skripta dodaje delove: `--with` pri pravljenju i `make add` za postojeći
  projekat — oblik se dogovara kad postoji drugi template.
- Nuxt ili Astro za sajt kao jedini template.
