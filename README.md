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
  Makefile      zna portove ovog projekta: make setup, make up, make web, make ports
  api/          Laravel backend, .env napisan za ovaj projekat
  web/          Vue frontend, .env napisan za ovaj projekat
  infra/        deljeni server stack (preskače se sa --no-infra)
  internal-mobile-app/
                Expo aplikacija za interne korisnike, .env.local gađa ovaj
                API (preskače se sa --no-mobile)
```

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
| 8 | `npm ci` za mobilnu aplikaciju (ako postoji) |

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

### 5. Mobilna aplikacija (interni korisnici)

```
make mobile-ios       sagradi development build i pokreni ga na iOS simulatoru
make mobile-android   isto na Android emulatoru (pokreni ga sa -no-audio)
make mobile           samo Metro, kad je build već instaliran
```

Aplikacija ne radi u Expo Go — prvi put se gradi native build (par minuta), posle
je dovoljan `make mobile`. Za iOS treba Xcode, za Android Android Studio i
emulator. Prijava je istim nalozima kao web.

Aplikacija se zove kao projekat (`client_hub` → „Client Hub", ime ispod ikonice
i u tekstovima dozvola). Bundle id i Android package ostaju
`com.example.backoffice` dok klijent nema naloge — menjaju se u koraku 0 uputstva
za push, jer Apple i Firebase vežu ključeve baš za njih.

**Na fizičkom telefonu** `localhost` je sam telefon. U
`internal-mobile-app/.env.local` upiši LAN adresu Mac-a
(`ipconfig getifaddr en0`, npr. `EXPO_PUBLIC_API_URL=http://192.168.1.23:8000/api`)
i restartuj Metro; telefon i Mac moraju biti na istom Wi-Fi-ju. Detalji u
`internal-mobile-app/README.md`. Sve ostalo — struktura, testovi,
Maestro flowovi — je u `internal-mobile-app/README.md` i `AGENTS.md`.

**Push obaveštenja** su podržana do kraja (backend, aplikacija, testovi), ali
nisu vezana ni za čiji nalog: Expo projekat, Firebase i Apple APNs ključ se
podešavaju po projektu, kad klijent ima naloge. Uputstvo korak po korak:
`internal-mobile-app/docs/push-notifications.md`.

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
| `localhost:8081` | Metro, mobilna aplikacija (`make mobile`) |
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
| `--no-mobile` | preskoči `internal-mobile-app/` — projekat bez mobilne aplikacije |
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
