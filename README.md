# project starter

Jedna komanda koja sklapa nov klijentski projekat — backend, frontend i infra —
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

---

## Šta dobiješ

```
fg-projects/client_hub/
  Makefile      zna portove ovog projekta: make setup, make up, make web, make ports
  api/          Laravel backend, .env napisan za ovaj projekat
  web/          Vue frontend, .env napisan za ovaj projekat
  infra/        deljeni server stack (preskače se sa --no-infra)
```

**Pravi samo fajlove.** Nijedan kontejner se ne gradi ni ne diže. Traje par
sekundi. Kad hoćeš da ga digneš:

```
cd client_hub && make setup
```

**Nijedan folder nije git repo.** Template se klonira zbog sadržaja, pa mu se
`.git` briše — projekat kreće bez istorije i bez remote-ova. Kad imaš gde da ga
gurneš:

```
cd api && git init && git add -A && git commit -m "Initial commit"
git branch -M main && git remote add origin <url> && git push -u origin main
```

---

## Imena i portovi

**Jedna promenljiva imenuje sve.** `COMPOSE_PROJECT_NAME` u `api/.env` daje
`client_hub-php-1`, `client_hub-postgres-1`, volumene `client_hub_postgres-data`
i image `client_hub/php:local`. Zato dva projekta mogu da rade uporedo.

**Jedan broj daje portove.** Svaki projekat dobija blok od deset, počev od 8100:

| | |
| --- | --- |
| `base` | API |
| `base+1` | postgres |
| `base+2` | test baza |
| `base+3` | redis |
| `base+4` | Grafana |
| `base+5` | Alloy |
| `base+6` | Vite |

Blok se bira automatski — preskaču se i portovi na kojima nešto sluša i blokovi
koje je uzeo neki susedni projekat. Ugašen projekat ne drži nijedan socket, a i
dalje polaže pravo na svoj blok, pa se gleda i `Makefile` susednih projekata.

**Zato drži sve projekte pod jednim korenom.** Skeniranje vidi samo folder u
koji upisuje; projekat u drugom korenu mu je nevidljiv i blok može da se dodeli
dvaput. Ako ih ipak razdvajaš, zadaj `--port-base` ručno.

---

## Opcije

| | |
| --- | --- |
| `--port-base N` | ručno zadaj blok umesto automatskog |
| `--dir PATH` | gde se pravi folder; jače od `$PROJECTS_DIR`, preskače prompt |
| `--no-infra` | preskoči infra repo — kad projekat ide na server koji ga već vrti |
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
