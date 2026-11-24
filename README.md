# project starter

Jedna komanda koja sklapa nov klijentski projekat — backend, frontend, mobilnu
aplikaciju za interne korisnike i infra —
iz naših template repoa, sa svojim imenom, svojim kontejnerima i svojim
portovima.

```
./new-project.sh client_hub
```

Bez argumenata pita za ime i destinaciju, pa radi i iz dvoklika na
`new-project.command`.

---

## Šta ti treba

| | |
| --- | --- |
| `bash`, `git` | uvek |
| `docker` | uvek (proverava se da postoji) |
| `make` | samo za `--setup` i kasnije za rad na projektu |
| pristup našim GitHub repoima | `git clone` ide na njih |

Radi na macOS-u, Linuxu i Git Bash-u na Windowsu. Nema GNU-only flagova,
`realpath`-a ni `sed -i`.

---

## Kako se pokreće

**Dvoklik** na `new-project.command`. macOS nema „pokreni" za `.sh`, pa Finder
na dvoklik otvara editor — `.command` se otvara u Terminalu. Omotač nema svoju
logiku, samo prosleđuje argumente.

> Ako si skinuo ZIP sa GitHuba umesto `git clone`, macOS je fajlovima okačio
> `com.apple.quarantine` i dvoklik javlja „unidentified developer". Prvi put
> otvori desnim klikom → **Open**, ili jednom pusti:
> `xattr -d com.apple.quarantine new-project.command`

**Iz terminala:**

```
./new-project.sh                      pita za ime i destinaciju
./new-project.sh client_hub           pita samo za destinaciju
./new-project.sh client_hub --dir ~/Desktop/fg-projects
```

**Ime** sme da ima mala slova, cifre i `_`, i počinje slovom: `client_hub`, ne
`client-hub` ni `ClientHub`. Ime postaje i ime baze i korisnika u Postgresu, gde
crtica traži navodnike u svakom SQL-u.

---

## Šta dobiješ

```
fg-projects/client_hub/
  CLAUDE.md, .mcp.json, .claude/
                Claude Code iz root-a zna sve foldere (vidi ispod)
  Makefile      zna portove ovog projekta: make setup, make up, make web, make ports
  api/          Laravel backend, .env napisan za ovaj projekat
  web/          Vue frontend, .env napisan za ovaj projekat
  infra/        deljeni server stack (preskače se sa --no-infra)
  internal-mobile-app/
                INTERNA Expo aplikacija — za zaposlene (korisnici admin
                panela); samo uz --with-internal-app
  external-mobile-app/
                EKSTERNA Expo aplikacija — za krajnje korisnike (kupci,
                građani, članovi); samo uz --with-external-app
```

**Mobilne aplikacije su opcione, obe.** Većina projekata je samo Laravel + Vue,
pa bez flagova nema nijedne. Pokrenuta bez argumenata (dvoklik na
`new-project.command`), skripta posle imena i destinacije pita za svaku
posebno — „Interna mobilna aplikacija?" i „Eksterna mobilna aplikacija?" —
sa „ne" kao podrazumevanim odgovorom. Backend je uvek isti: deo API-ja za
eksternu aplikaciju i admin strana „Korisnici aplikacije" postoje i kad
aplikacija nije izabrana, pa može da se doda kasnije.

**Claude Code se pokreće iz root-a projekta.** `claude` u `client_hub/` i
samo kažeš šta treba — root `CLAUDE.md` je mapa foldera i za svaki kaže koji
fajl s pravilima da pročita pre izmene (`api/CLAUDE.md` + `.ai/rules`,
`web/AGENTS.md`, `internal-mobile-app/AGENTS.md`, `external-mobile-app/AGENTS.md`).
Claude Code čita
`.mcp.json` i `.claude/` samo iz foldera u kom je sesija pokrenuta, pa ih
root dobija svoje:

- `.mcp.json` — MCP serveri svih template-a na jednom mestu: laravel-boost
  (radi u `php` kontejneru, treba `make up`), nuxt-ui, zod, playwright i
  maestro kad postoji mobilna aplikacija.
- `.claude/skills/` — symlinkovi na skillove iz `api/`, `web/` i mobilnih
  aplikacija. Skill se menja u folderu kome pripada. Isti vendorovani skill
  dve aplikacije linkuje se jednom; različiti skillovi istog imena zaustavljaju
  skriptu (zato je eksterni `new-external-feature`, a interni `new-feature`).
- `.claude/settings.json` — uključen Expo plugin, kad postoji mobilna aplikacija.

Serveri su upisani u skripti, ne spojeni iz template-a. Kad neki template
dobije nov MCP server, skripta to javi upozorenjem — tad ga dodaj u
`new-project.sh`. Sesija pokrenuta u jednom folderu i dalje radi, ali tad
dobija samo alate tog foldera.

**Pravi samo fajlove.** Nijedan kontejner se ne gradi ni ne diže. Traje par
sekundi. Kad hoćeš da ga digneš — vidi *Prvi put, korak po korak* ispod:

```
cd client_hub && make init
```

**Nijedan folder nije git repo.** Template se klonira zbog sadržaja, pa mu se
`.git` briše — projekat kreće bez istorije i bez remote-ova. Kad imaš gde da ga
gurneš:

```
cd api && git init && git add -A && git commit -m "Initial commit"
git branch -M main && git remote add origin <url> && git push -u origin main
```

---

## Prvi put, korak po korak

Redosled je bitan samo na jednom mestu — projekat mora da postoji pre nego što
ga dižeš. Sve ostalo je jedna komanda.

### 1. Napravi projekat

```
./new-project.sh client_hub
```

Ili dvoklik na `new-project.command` pa odgovori na dva pitanja. Traje par
sekundi i **ništa ne pokreće** — samo kopira template i upiše `.env`-ove.

Ako hoćeš da odmah i digne, dodaj `--setup`; to je isto što i korak 2.

### 2. Digni ga

```
cd ~/Desktop/fg-projects/client_hub
make init
```

Traje par minuta prvi put, jer se gradi PHP image. Redom radi ovo:

| | |
| --- | --- |
| 1 | sagradi image i digne 7 kontejnera (nginx, php, horizon, scheduler, postgres, postgres-test, redis) |
| 2 | `composer install` |
| 3 | generiše `APP_KEY` |
| 4 | pusti migracije |
| 5 | poveže `storage` simlink (avatari se odatle serviraju) |
| 6 | **seeduje prvog administratora** |
| 7 | `npm install` za frontend |
| 8 | `npm ci` za svaku izabranu mobilnu aplikaciju |
| 9 | uz eksternu aplikaciju: demo nalozi (`mobile:demo-accounts`) iz `MOBILE_DEMO_EMAILS` |

Korak 6 je ono zbog čega postoji `make init` a ne samo `make up`: bez njega baza
je prazna i nemaš čime da se prijaviš.

### 3. Prijavi se

```
make ports        podseti se šta je na kom portu
```

Backend je na `http://localhost:8000`, dokumentacija na `/docs/api`. Nalog dolazi
iz `api/database/seeders/UserSeeder.php`:

```
uros.minic@fifthguild.com / password
```

> **Menjaš adresu?** Izmeni `UserSeeder.php` **pre** `make init`. Seeder je
> idempotentan — preskače nalog koji već postoji — pa ponovno pokretanje posle
> izmene neće napraviti novi. Tada ide `make -C api fresh` (briše bazu) ili
> `make -C api artisan c="admin:create ..."` za dodatni nalog.

### 4. Pokreni frontend

```
make web
```

Vite na `http://localhost:5173`, već podešen da gađa API na 8000.

### 5. Mobilne aplikacije (ako su izabrane)

Dve različite aplikacije, za dve različite publike — nikad ih ne mešaj:

| | interna — `internal-mobile-app/` | eksterna — `external-mobile-app/` |
| --- | --- | --- |
| za koga | zaposleni (nalozi iz admin panela, `users`) | krajnji korisnici (kupci, građani; `mobile_users`) |
| prijava | email i lozinka, isti nalozi kao web | kod na mejl, Google, Apple; registracija u aplikaciji |
| jezik | srpski | srpski (podrazumevano) i engleski |
| API | `/api/...` | `/api/mobile/v1/...` — token jedne publike ne prolazi na rutama druge |
| repo | `dev-uros/expo-internal-ai-setup` | `dev-uros/expo-external-ai-setup` (fork interne) |
| Makefile | `internal-app-ios`, `internal-app-android`, `internal-app` | `external-app-ios`, `external-app-android`, `external-app` |

```
make internal-app-ios       sagradi development build interne aplikacije na iOS simulatoru
make external-app-android   isto za eksternu, na Android emulatoru (pokreni ga sa -no-audio)
make external-app           samo Metro, kad je build već instaliran
```

Aplikacije ne rade u Expo Go — prvi put se gradi native build (par minuta), posle
je dovoljan Metro. Obe koriste Metro na 8081, pa radi jedna po jedna. Za iOS treba
Xcode, za Android Android Studio i emulator.

Aplikacija se zove kao projekat (`client_hub` → „Client Hub", ime ispod ikonice
i u tekstovima dozvola). Kad projekat ima obe, interna je „Client Hub Interno",
da se ikonice razlikuju. Bundle id i Android package ostaju `com.example.*` dok
klijent nema naloge — menjaju se u koraku 0 uputstva za push, jer Apple, Google i
Firebase vežu ključeve baš za njih.

**Eksterna aplikacija lokalno:** nema lozinki. Kod za prijavu stiže na mejl, a
lokalno ga API piše u log (`api/storage/logs/laravel.log`). Demo nalozi iz
`MOBILE_DEMO_EMAILS` u `api/.env` (skripta ih upiše, `make init` ih napravi)
primaju fiksni kod `424242` i ne dobijaju mejl — njih koriste Maestro flowovi, a
u produkciji App Store i Play recenzenti. Google i Apple dugmad su skrivena dok
projekat nema te naloge: `external-mobile-app/docs/sign-in.md`.

**Na fizičkom telefonu** `localhost` je sam telefon. U `.env.local` aplikacije
upiši LAN adresu Mac-a (`ipconfig getifaddr en0`, npr.
`EXPO_PUBLIC_API_URL=http://192.168.1.23:8000/api`) i restartuj Metro; telefon i
Mac moraju biti na istom Wi-Fi-ju. Sve ostalo — struktura, testovi, Maestro
flowovi — je u `README.md` i `AGENTS.md` svake aplikacije.

#### Tri aplikacije na istom telefonu

Iz istog koda prave se tri aplikacije koje stoje jedna pored druge: **Ime (Dev)**,
**Ime (Test)** i **Ime**. Svaka ima svoj bundle id, svoj API i svoje Sentry
okruženje. Lokalni rad (`make *-app-ios`, `make *-app-android`) je uvek dev
varijanta (`APP_VARIANT=development` u `.env.local`). Test i produkciju pravi
EAS: `npm run build:preview` i `npm run build:production` u folderu aplikacije.
Lokalno rade sve tri i bez naloga. Detalji su u `docs/builds.md` svake aplikacije.

#### Nalozi koje mobilna aplikacija traži po projektu

Template nije vezan ni za čiji nalog. Sve radi lokalno bez njih, ali za
sledeće stvari projekat mora da ima **svoje** naloge, najbolje na klijentovu ili
firminu organizaciju, nikad lične:

| Nalog | Za šta | Bez njega | Uputstvo |
| --- | --- | --- | --- |
| **Expo** (organizacija na expo.dev) | EAS build-ovi (dev, test, produkcija), push token, OTA update-ovi | nema push-a, build-a na Expo serverima ni OTA-a | `docs/builds.md`, `docs/updates.md` |
| **Firebase** projekat (besplatan) | push na Androidu | Android ne dobija push | `docs/push-notifications.md` |
| **Apple Developer** (plaćen) | push na iOS-u, build na iPhone, TestFlight, App Store | iOS ne dobija push, nema instalacije na iPhone ni distribucije | `docs/push-notifications.md`, `docs/builds.md` |
| **Google Play Developer** (jednokratna taksa) | objava na Google Play | nema Play Store-a (test APK i dalje radi) | `docs/builds.md` |
| **Sentry** (besplatan plan: 5.000 grešaka mesečno) | prijave padova i grešaka iz release build-ova | aplikacija radi, ali greške korisnika ne vidi niko | `docs/sentry.md` |
| **Google Cloud** projekat (besplatan) — samo eksterna | „Nastavi uz Google" | dugme je skriveno, prijava kodom radi | `docs/sign-in.md` |
| **Apple Developer** — eksterna | „Nastavi uz Apple" (iOS) | dugme je skriveno | `docs/sign-in.md` |
| **SMTP** za produkciju — eksterna | kodovi za prijavu u prave sandučiće | lokalno kod ide u log API-ja | `api/.env` (`MAIL_*`) |

#### Ažuriranja: OTA i obavezno ažuriranje

Oba su ugrađena od prve verzije, jer aplikacija koja izađe bez njih ne može
kasnije da ih dobije:

- **OTA (EAS Update):** ispravka u JS-u stiže na telefone bez prodavnice
  (`npm run update:preview`, `npm run update:production`), svaka varijanta na
  svom kanalu. Isključeno je dok projekat nema Expo nalog. Uz svaku native
  promenu diže se `version` u `app.json`.
- **Obavezno ažuriranje:** svaka aplikacija ima svoj minimum u `.env` API-ja
  (`MOBILE_INTERNAL_IOS_MINIMUM_VERSION`, `MOBILE_EXTERNAL_ANDROID_MINIMUM_VERSION`…).
  Starija verzija prikazuje samo „Potrebno je ažuriranje" sa linkom ka
  prodavnici. Radi bez ikakvog naloga.

Detalji su u `docs/updates.md` svake aplikacije.

Putanje su u folderu aplikacije. Push je podržan do kraja (backend,
aplikacija, testovi), a Sentry je ugrađen i ćuti dok su
`EXPO_PUBLIC_SENTRY_DSN`, `SENTRY_ORG` i `SENTRY_PROJECT` prazni — oba čekaju
samo naloge. Tajne (Sentry auth token, Firebase service account, APNs ključ)
idu samo u EAS, nikad u repo.

### Svaki sledeći put

```
make up      digni
make down    ugasi
```

`make init` se pušta jednom po projektu.

---

## Kad zapne

**`docker: Cannot connect to the Docker daemon`** — Docker Desktop ne radi.
Pokreni ga i sačekaj da ikona prestane da se animira.

**`there is already a project called 'x' in ...`** — u tom folderu već postoji
projekat tog imena. Uzmi drugo ime ili obriši stari folder. Ime je i
`COMPOSE_PROJECT_NAME`, pa dva projekta istog imena dele kontejnere čak i iz
različitih foldera.

**`port is already allocated`** — drugi projekat je podignut na istim portovima.
`make down` u njemu, ili napravi ovaj sa `--port-base 8100` pa mogu uporedo.
Skripta te i pri pravljenju upozori ako nešto već sluša.

**`git clone` traži lozinku** — nemaš pristup nekom od template repoa. Traži pristup,
ili proveri da ti je SSH ključ/token podešen za GitHub. Ako clone pukne, skripta
obriše polovičan projekat, pa posle samo pusti istu komandu ponovo.

**`booting it failed`** posle `--setup` — fajlovi su napravljeni i ostaju, samo
dizanje nije uspelo (najčešće Docker ne radi). Popravi uzrok pa `make init` u
folderu projekta.

**Dvoklik javlja „unidentified developer"** — skinuo si ZIP umesto `git clone`.
Vidi napomenu o `com.apple.quarantine` gore.

**`make: command not found`** — na macOS-u dolazi sa Xcode Command Line Tools:
`xcode-select --install`.

---

## Imena i portovi

**Jedna promenljiva imenuje sve.** `COMPOSE_PROJECT_NAME` u `api/.env` daje
`client_hub-php-1`, `client_hub-postgres-1`, volumene `client_hub_postgres-data`
i image `client_hub/php:local`. Zato dva projekta ne mogu da se pregaze — svaki
ima svoje kontejnere, svoje volumene i svoju mrežu.

**Portovi su svuda isti.** Svaki projekat koristi iste, poznate brojeve:

| | |
| --- | --- |
| `localhost:8000` | Laravel API (`/docs/api`, `/horizon`, `/pulse`) |
| `localhost:5173` | Vite, frontend |
| `localhost:8081` | Metro, mobilna aplikacija (`make internal-app` / `make external-app`, jedna po jedna) |
| `localhost:5433` | postgres |
| `localhost:5434` | test baza |
| `localhost:6379` | redis |
| `localhost:3000` | Grafana (`make observe`) |

Skripta ih ne dira — to su defaulti iz samog templatea. Postgres je na 5433 a ne
5432 namerno, jer je 5432 najčešće zauzet lokalnom instalacijom.

**Zato možeš da radiš na jednom projektu u datom trenutku.** Ime projekta
razdvaja kontejnere i podatke, ali port na hostu drži tačno jedan proces na celoj
mašini. Ako pokreneš drugi projekat dok prvi radi, `docker compose` javi:

```
Error: Bind for 0.0.0.0:8000 failed: port is already allocated
```

Glasno i bezopasno — ništa se ne pokvari, samo se ne digne. Rešenje je `make
down` u onom drugom.

**Kad ti stvarno trebaju dva uporedo**, drugom pri pravljenju daj `--port-base`:

```
./new-project.sh acme --port-base 8100
```

Dobija blok od deset: API `8100`, postgres `8101`, test baza `8102`, redis
`8103`, Grafana `8104`, Alloy `8105`, Vite `8106`. Isti raspored za bilo koju
bazu, pa je `base+6` uvek frontend.

`make ports` u svakom projektu ispiše šta je gde, pa nema šta da se pamti.

---

## Opcije

| | |
| --- | --- |
| `--port-base N` | pomeri portove u blok od deset odavde — za dva projekta uporedo |
| `--dir PATH` | gde se pravi folder; jače od `$PROJECTS_DIR`, preskače prompt |
| `--no-infra` | preskoči infra repo — kad projekat ide na server koji ga već vrti |
| `--with-internal-app` | dodaj `internal-mobile-app/` — Expo aplikacija za zaposlene |
| `--with-external-app` | dodaj `external-mobile-app/` — Expo aplikacija za krajnje korisnike |
| `--no-mobile` | uklonjen: bez gornja dva flaga projekat ionako nema mobilnu aplikaciju (skripta to ispiše) |
| `--setup` | i sagradi kontejnere, migriraj, instaliraj `node_modules` |

Destinacija se bira na tri nivoa, od jačeg ka slabijem: `--dir PATH` za jedan
poziv, `PROJECTS_DIR` iz okruženja za stalno, i prompt sa `~/Desktop/fg-projects`
kao ponuđenim odgovorom. Putanja se kreira ako ne postoji; ako već postoji
projekat sa tim imenom, javlja i staje.

---

## Šta ovo svesno ne radi

**Ne prati template.** Pošto se `.git` briše, projekat i template nemaju
zajedničkog pretka — `git merge` bi javio konflikt na svakom fajlu. Popravka u
templateu se prenosi kopiranjem izmene. To je cena za čist start i za klon koji
traje sekunde umesto minuta.

**Ne pravi repo na GitHubu.** Nema `gh` CLI-ja u igri, pa prazan repo praviš
sam, a skripta ti na kraju ispiše komande za `git init` i `push`.

**Ne postavlja produkciju.** Runbook od praznog VPS-a do svih servisa je u infra
repou, `docs/server-setup.md`.
