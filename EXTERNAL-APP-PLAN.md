# Plan: eksterna mobilna aplikacija

Template za aplikaciju krajnjih korisnika (kupci, građani, članovi): prijava
kodom na email ili preko Apple-a i Google-a, srpski i engleski, početna strana
i podešavanja. Sve ostalo je ista infrastruktura kao u internoj aplikaciji.

Uzor za funkcionalnosti je reciklomat (`reciklomat-mob` i `reciklomat/api`).
Uzor za infrastrukturu je naš interni template. Iz reciklomata se prepisuje ono
što valja, a ne prenosi se ono što je tamo loše (spisak je na kraju).

Status: plan je potvrđen 2026-11-24 i urađen istog dana (faze 1–5); repo
`dev-uros/expo-external-ai-setup` još nije napravljen na GitHub-u, fork je lokalno u
`~/generators/expo-external-ai-setup`.

**Odluke iz odeljka „Potvrđene odluke" na kraju imaju prednost nad svim
ostalim u ovom fajlu.** Gde se tekst ispod razlikuje (oznake ❓, isticanje
tokena, jedan tok prijave, uslovi, `mobile-app/`), važi taj odeljak.

---

## 1. Šta pravimo

| deo | repo | folder u projektu |
| --- | --- | --- |
| mobilna aplikacija | `dev-uros/expo-external-ai-setup` (nov, fork internog) | `mobile-app/` ❓ |
| backend | postojeći `laravel-backend-ai-setup` | `api/` |
| admin | postojeći `vue-front-ai-setup` (opciono, faza 6) | `web/` |
| project-starter | flag i povezivanje | — |

### Zašto fork internog, a ne reciklomat

Reciklomat ima dobru prijavu, ali je slab na svemu oko nje:
- jedan neotipiziran stack;
- nema 401 obrade;
- nema env konfiguracije, varijanti, OTA-a, Sentry-ja, testova ni dark moda;
- WebView splash traje 4–7 s.

Interni template sve to već ima i testirano je. Zato iz internog uzimamo kostur,
a iz reciklomata prepisujemo samo prijavu i obrasce lokalizacije.

---

## 2. Mobilna aplikacija

### 2.1 Ostaje iz internog templatea, bez izmena

- Expo SDK 58, Expo Router, NativeTabs, TanStack Query, Zod, Zustand, Figtree,
  light/dark/system tema, error boundary.
- Tri varijante (dev, test, production), sa posebnim ID-jevima, imenima i
  šemama; `eas.json` sa kanalima.
- OTA (`update:preview` / `update:production`) i ekran za obavezno ažuriranje.
- Sentry (samo release buildovi), push sa ekranom za stanje dozvole na
  podešavanjima.
- HTTP klijent:
  - 401 odjavljuje korisnika;
  - nedostupnost servera pri pokretanju čuva token;
  - `keepOnSignOut`.
- Jest, Maestro, `AGENTS.md`, skill `new-feature`, `docs/builds.md`,
  `docs/sentry.md`, `docs/updates.md`, `docs/push-notifications.md`.

### 2.2 Uklanja se

- Feature `users` (lista i detalj korisnika) i adminske izmene profila.
- Prijava lozinkom.
- `shortcuts` ❓, ako su vezani za internu upotrebu.

### 2.3 Novo: prijava

Ekrani u grupi `(auth)`:

1. **Dobrodošlica / prijava:**
   - logo;
   - polje za email i dugme „Nastavi";
   - „Nastavi uz Apple" (samo na iOS-u, ako je `isAvailableAsync`);
   - „Nastavi uz Google";
   - prekidač jezika;
   - tekst „Nastavkom prihvatate [Uslove korišćenja] i [Politiku privatnosti]"
     sa linkovima ❓.
2. **Kod:**
   - 6 cifara: skriveni input sa `textContentType="oneTimeCode"`, autofill i
     automatsko slanje (komponenta iz reciklomata);
   - **„Pošalji ponovo" sa odbrojavanjem** (60 s, vrednost dolazi sa servera,
     `retry_after`);
   - „Promeni email".
3. **Dovršavanje profila:** samo pri prvoj prijavi, kad nalog nema ime ❓. Polje
   je ime; Apple i Google ga popunjavaju sami kad ga pošalju.

**Jedan tok za prijavu i registraciju** (razlika u odnosu na reciklomat):
- **Email:** kod se uvek šalje na unetu adresu. Ako nalog ne postoji, pravi se
  kad se kod potvrdi. Nema posebnog ekrana za registraciju. Server ne otkriva
  da li nalog postoji, pa nema `account_exists`.
- **Apple i Google:** jedan endpoint po provajderu, koji prijavljuje ili pravi
  nalog. Nema „404 pa registracija".
- **Odgovor:** kad se nalog tek napravi, server vraća `{ token, user, created: true }`,
  a aplikacija tada vodi na dovršavanje profila ako ime nedostaje.

**Prepisuje se iz reciklomata:**
- lenjo učitavanje Google i Apple modula, pa dugme nestaje u buildu bez njih;
- čuvanje Apple imena iz prve autorizacije (Apple ga šalje samo jednom);
- klasifikacija grešaka po HTTP statusu, ne po tekstu poruke: 409 znači „nalog
  postoji sa drugim načinom prijave, uđi kodom", 422 je neispravan token, 503
  je da provajder nije dostupan;
- `signOut()` pre `signIn()` na Google-u, da se uvek ponudi izbor naloga.

**Konfiguracija:**
- `@react-native-google-signin/google-signin` kao config plugin sa
  `iosUrlScheme`, i to **po varijanti** jer svaka ima svoj bundle ID.
- Client ID-jevi idu iz `EXPO_PUBLIC_GOOGLE_*` u `app.config.ts`.
- Bez client ID-ja dugme se ne prikazuje i aplikacija i dalje radi. Isti obrazac
  kao Sentry i push: template nije vezan ni za jedan nalog.
- Apple prijava: `ios.usesAppleSignIn` i `nonce` (SHA-256), koji server proverava.

### 2.4 Novo: lokalizacija

- **Jezici:** `i18next` + `react-i18next` + `expo-localization`, sa jezicima
  `sr` (latinica) i `en`.
- **Početni jezik:** jezik telefona ako je srpski, hrvatski, bosanski ili
  crnogorski, inače engleski ❓.
- **Izbor jezika:**
  - čuva se lokalno i učitava se **pre** prvog prikaza, iza splash ekrana, da
    ekran ne trepne na pogrešnom jeziku;
  - svaki zahtev nosi `Accept-Language`;
  - pri prijavi i promeni jezika jezik se šalje serveru (`locale` na nalogu), da
    bi email i push stizali na istom jeziku;
  - posle promene jezika invalidiraju se svi upiti, pa se sadržaj koji prevodi
    server osveži.
- **Prevodi:** fajlovi `src/i18n/sr.json` i `en.json` su po feature-ima, a test
  proverava da oba imaju iste ključeve.
- **Množina:** i18next plurals (`_one` / `_few` / `_other`), ne ručna pravila
  kao u reciklomatu.
- **Datumi i brojevi:** `Intl` sa `sr-Latn-RS` / `en-GB` iz jedne pomoćne
  funkcije. Gola `sr-RS` daje ćirilicu.
- **Tekstovi dozvola** (kamera, galerija, notifikacije) prevode se kroz
  `expo-localization` `locales` u app configu, jer ih prikazuje sistem.
- **Interna aplikacija:** postojeći srpski tekstovi prelaze u i18n fajlove.

### 2.5 Novo: ekrani

- **Početna:** pozdrav po imenu i doba dana, pull to refresh i prazno mesto
  („ovde ide sadržaj projekta").
- **Podešavanja:**
  - *Nalog:* avatar (kamera ili galerija, kao u internom), ime i email (samo
    za čitanje);
  - *Aplikacija:* jezik, tema, notifikacije (stanje i test push, iz internog);
  - *Podrška:* Uslovi korišćenja i Politika privatnosti (URL po jeziku iz
    `EXPO_PUBLIC_*`), verzija aplikacije;
  - *Opasna zona:* odjava i brisanje naloga.
- **Brisanje naloga** (App Store i Play to traže):
  - prvo potvrda, pa brisanje;
  - za nalog vezan za Apple prvo ponovna Apple autorizacija zbog
    `authorization_code`, a ako je korisnik otkaže, brisanje se ipak nastavlja;
  - pregled „šta gubite" ostaje kao mesto za domenski sadržaj, a u templateu je
    samo potvrda.
- **Odjava:** odjavljuje sa Google-a, a server briše push token uređaja.

### 2.6 Testovi

- **Jest:**
  - OTP komponenta, odbrojavanje i klasifikacija grešaka;
  - jezik: početni, promena, header i isti ključevi u oba fajla;
  - tok prijave sa mockovanim API-jem i dovršavanje profila;
  - brisanje naloga.
- **Maestro:**
  - prijava kodom: demo nalog sa fiksnim kodom (vidi 3.2), pa Maestro ne čita
    mejl;
  - dovršavanje profila, promena jezika (provera prevedenog teksta), tema,
    odjava, brisanje naloga.
  - Google i Apple se ne testiraju u Maestru; proveravaju se ručno na uređaju
    kad postoje nalozi.

---

## 3. Backend (Laravel template)

Sve se dodaje u postojeći template, odvojeno od internih korisnika.

### 3.1 Model i razdvajanje publike — kritično

- **Tabela `mobile_users`:**
  - `id`, `name` (nullable), `email` (unique, nullable posle brisanja, uvek
    malim slovima);
  - `google_id`, `apple_id` (unique, nullable), `apple_refresh_token`
    (encrypted);
  - `locale` (`sr`|`en`), `avatar_path`;
  - `terms_accepted_at` ❓, `is_demo`, `blocked_at`, `last_seen_at`;
  - soft deletes.
- **Model `MobileUser`:**
  - `HasApiTokens`;
  - `#[Fillable([])]`, a upisi idu kroz repozitorijum, kao u reciklomatu.
- **Audience middleware:**
  - `EnsureMobileUser` i `EnsureInternalUser`.
  - **Postojeće rute moraju da dobiju `EnsureInternalUser`.** Sanctum
    razrešava token u bilo koji model, pa bi bez toga token kupca prošao
    `auth:sanctum` na adminskim rutama.
  - Test proverava da nijedna ruta pod `auth:sanctum` nema mešanu publiku.
- **Rute:** `/api/mobile/v1/...`, kako je dogovoreno u `PLAN.md`. Interne rute
  ostaju gde su.

### 3.2 Prijava kodom

**Rute** (javne, sa throttle-om):

| ruta | šta |
| --- | --- |
| `POST mobile/v1/auth/email/code` | `{email, locale}` → kod na mejl; uvek 200 sa `{retry_after}` |
| `POST mobile/v1/auth/email/verify` | `{email, code, locale, device}` → `{token, user, created}` |

**Kodovi:**
- Tabela `mobile_otp_codes`: email, `code_hash` (bcrypt), `attempts`,
  `expires_at`, `sent_at`.
- Važi 10 minuta, dozvoljeno je 5 pogrešnih pokušaja, a živi samo jedan kod po
  adresi.
- **Pokušaji se broje atomski** (`increment` uz `where attempts < 5`).
- **Ponovno slanje:** posle 60 s; ranije vraća 429 sa `retry_after`, a
  aplikacija prikazuje odbrojavanje.
- **Limiteri:**
  - zahtev za kod: 5 na sat po adresi i 20 na sat po IP-ju;
  - provera koda: 10 na 10 minuta po adresi i 30 po IP-ju;
  - prijava preko provajdera: 10 u minutu po IP-ju.

**Mejl:**
- Notifikacija ide u red i **šifrovana je** (`ShouldBeEncrypted`), lokalizovana
  na jezik iz zahteva, sa Blade šablonom koji prati postojeće mejlove u
  templateu.
- **Kod se ne loguje:** cela tela `mobile/v1/auth/*` zahteva ne ulaze u
  request log (proveriti `RequestContext` / `RedactProcessor`).

**Demo nalog za App Store / Play review:**
- `MOBILE_DEMO_EMAILS` i `MOBILE_DEMO_CODE`; kod radi samo za `is_demo` naloge
  i mejl se ne šalje.
- Nalozi se prave komandom `php artisan mobile:demo-accounts`.
- **Isti mehanizam koristi Maestro lokalno.**

### 3.3 Apple i Google

- `POST mobile/v1/auth/google` — `{id_token, locale, device}`.
- `POST mobile/v1/auth/apple` — `{id_token, authorization_code?, nonce, given_name?, family_name?, locale, device}`.
- **Provera tokena bez poziva provajderu**, preko JWKS (`firebase/php-jwt`,
  dekoder iz reciklomata: keš ključeva, ponovno preuzimanje na nepoznat `kid`
  najviše jednom u minutu, 60 s tolerancije sata).
- **`aud` je lista:**
  - za Google web, iOS i Android client ID;
  - za Apple bundle ID-jevi sve tri varijante.
- **Apple `nonce`** se proverava. Google native SDK ga ne podržava pouzdano, pa
  tamo ostaje bez njega.
- **Povezivanje sa postojećim nalogom** (iz reciklomata):
  - pretraga po `sub`, pa po email-u;
  - spaja se samo kad je provajder autoritativan za adresu: Gmail ili `hd` za
    Google, iCloud za Apple;
  - inače 409 „uđite kodom";
  - upis je uslovni `UPDATE`, otporan na istovremene zahteve.
- **Apple refresh token** se uzima iz `authorization_code` posle commita i
  čuva šifrovano; koristi se za opoziv pri brisanju naloga. Neuspeh ne obara
  prijavu.
- **Env:** `GOOGLE_OAUTH_CLIENT_IDS`, `APPLE_CLIENT_IDS`, `APPLE_TEAM_ID`,
  `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY_BASE64`. Kad su prazni, ruta vraća 503
  sa jasnom porukom.

### 3.4 Tokeni, sesija, nalog

- **Isticanje tokena** (reciklomat ga nema): 90 dana neaktivnosti ❓. Token se
  produžava najviše jednom dnevno pri korišćenju, istekli tokeni se brišu
  zakazanom komandom `sanctum:prune-expired`, a aplikacija na 401 već odjavljuje.
- **Rute za nalog i uređaj:**

  | ruta | šta |
  | --- | --- |
  | `GET mobile/v1/me` | korisnik |
  | `PATCH mobile/v1/me` | ime, jezik |
  | `POST` / `DELETE mobile/v1/me/avatar` | profilna slika |
  | `POST mobile/v1/auth/logout` | briše token i **push token tog uređaja** |
  | `DELETE mobile/v1/me` | brisanje naloga |
  | `PUT mobile/v1/device` | push token za uređaj sesije; obrazac iz internog `auth/device`, bez ID-ja u putanji |
  | `POST mobile/v1/device/test-push` | test notifikacija |

- **Brisanje naloga:**
  - soft delete i anonimizacija: email, ime, ID-jevi provajdera i avatar idu
    na `null`;
  - brišu se tokeni, uređaji i kodovi;
  - Apple opoziv ide kao šifrovan job sa ponavljanjem.
  - Ista adresa posle toga može ponovo da se registruje.
- **Blokiranje:** `blocked_at` se proverava u `EnsureMobileUser` na svakom
  zahtevu, a blokada briše tokene.
- **Uređaji:** tabela `mobile_user_devices`, a nevažeći Expo token se briše na
  `DeviceNotRegistered`.

### 3.5 Lokalizacija na backendu

- **Middleware `SetLocale`:** jezik iz `Accept-Language`, `sr` ili `en`, uz
  podrazumevani `sr`.
- **Prevodi:** `lang/sr/*.php` i `lang/en/*.php`, i za validaciju. Nazivi polja
  su prevedeni, ne zakucani na srpskom.
- **Jezik naloga:** mejl i push koriste `locale` sa naloga, koji se ažurira pri
  svakoj prijavi i promeni jezika. Odgovor na zahtev koristi header.

### 3.6 Obavezno ažuriranje za dve aplikacije

Sada postoji jedan minimum po platformi, a sa dve aplikacije treba po aplikaciji:
- Ruta postaje `GET mobile/app-version/{app}/{platform}`, gde je `app`
  `internal` ili `external`.
- Env vrednosti:
  - `MOBILE_INTERNAL_IOS_MINIMUM_VERSION` itd.;
  - `MOBILE_EXTERNAL_IOS_MINIMUM_VERSION` itd.
- Interni template se menja da gađa `internal`. Ovo je mala izmena, a treba je
  uraditi pre nego što ijedan projekat izađe u produkciju.

### 3.7 Testovi

Feature testovi po uzoru na reciklomat:
- **Prijava kodom:** hash, isticanje, 5 pokušaja, jedan aktivan kod, cooldown,
  limiteri.
- **Mejl:** šifrovan je, prati jezik, a kod ne ulazi u log.
- **Google i Apple:** lažni JWKS i potpisani tokeni, `aud` lista, nonce,
  povezivanje i 409.
- **Publika:** token kupca dobija 403 na internim rutama i obrnuto.
- **Tokeni:** isticanje i produžavanje.
- **Nalog i uređaji:** brisanje sa anonimizacijom i Apple opozivom, blokada,
  uređaj, odjava briše push token.
- **Ostalo:** jezik, demo nalog.

---

## 4. Admin (Vue), opciono

Strana „Korisnici aplikacije" sa listom, pretragom, detaljem i
blokiranjem/odblokiranjem ❓. Bez nje admin ne vidi kupce, ali template radi i
bez nje. Predlog je da se uradi u fazi 6, ako je potrebna.

---

## 5. project-starter

- Repo `MOBILE_EXTERNAL_REPO`, folder `mobile-app/` ❓.
- **Flag** ❓: `--with-external-app` (opt-in, jer je većina projekata samo
  admin), ili isto kao interna, uključena po defaultu uz `--no-external-app`.
- **Pri pravljenju projekta:**
  - ime i bundle ID-jevi po projektu;
  - `.env.local` gađa lokalni API;
  - `make mobile-app`, `mobile-app-ios`, `mobile-app-android`;
  - red u root `CLAUDE.md` i `.mcp.json`.
- **Backend:** demo nalog se pravi pri `--setup`, a `.env.example` dobija nove
  `GOOGLE_*`, `APPLE_*` i `MOBILE_*` vrednosti.
- **`PLAN.md`:** red „eksterna aplikacija" prelazi u ✅.

---

## 6. Faze

| # | šta | gotovo kad |
| --- | --- | --- |
| 1 | Backend: `mobile_users`, publika, kod na mejl, tokeni sa isticanjem, `me`, uređaj, odjava, brisanje, jezik, demo nalog, min verzija po aplikaciji | testovi zeleni, interne rute zatvorene za kupce |
| 2 | Mobilni fork: uklanjanje internih feature-a, i18n (i u internom templateu, posebno), prijava kodom, dovršavanje profila, podešavanja, brisanje | Jest i Maestro zeleni na oba simulatora |
| 3 | Apple i Google: backend verifikacija i aplikacija, konfiguracija po varijanti | testovi sa lažnim tokenima zeleni; dugmad se skrivaju bez client ID-ja |
| 4 | Docs: `docs/sign-in.md` (Google Cloud, Apple Developer, SHA-1 po varijanti, review nalog), `docs/localization.md`, `AGENTS.md`, README; tabela „šta traži nalog" | — |
| 5 | project-starter: flag, Makefile, root CLAUDE.md, povezivanje na `.env` | nov projekat se diže sa obe aplikacije |
| 6 | (opciono) admin strana za korisnike aplikacije | — |

Google i Apple prijava se stvarno proveravaju tek sa nalozima, na uređaju.
Do tada važi isto kao za OTA i push: konfiguracija je spremna i proverena, sam
nalog nije.

---

## 7. Šta traži nalog

| | bez naloga | sa nalogom |
| --- | --- | --- |
| prijava kodom | radi lokalno (Mailpit / log mailer) | produkcijski SMTP |
| Google | dugme skriveno | Google Cloud projekat: OAuth consent screen, web client, iOS client po bundle ID-ju, Android client po paketu **i SHA-1 svakog potpisnog ključa** (debug, EAS, Play App Signing) |
| Apple | dugme skriveno | Apple Developer: Sign in with Apple capability na App ID-jevima, ključ (.p8) za opoziv |
| review | — | demo nalog i kod u App Store Connect / Play Console |
| push, OTA, Sentry | kao u internom | kao u internom |

---

## 8. Iz reciklomata se NE prenosi

**Mobilna aplikacija:**
- Nema 401 obrade, a mrežna greška pri pokretanju vodi na onboarding.
- Jezik telefona se ne čita; podrazumevani `sr` se primeni pre učitanog
  izbora; jezik sa naloga se nikad ne primeni.
- Promena jezika ne osvežava sadržaj koji prevodi server.
- `sr-RS` u `toLocaleDateString`, pa datumi izlaze na ćirilici; ručna množina.
- Poruke o greškama su zakucane u komponentama i biraju se po tekstu odgovora
  servera.
- Nema odbrojavanja za ponovno slanje koda.
- Registracija push tokena je zakopana u početnoj strani; odjava ne briše push
  token.
- WebView splash (4–7 s); `hideAsync` u renderu; onboarding na svakom
  pokretanju.
- Jedan neotipiziran stack; axios čita SecureStore na svakom zahtevu.
- Debug logovi sa celim odgovorom prijave.

**Backend:**
- Tokeni bez isticanja.
- OTP u request logu i nešifrovan u redu.
- Brojač pokušaja koji nije atomski.
- Jedan `aud`; nema nonce-a.
- Provera jedinstvenosti emaila osetljiva na velika i mala slova.
- Nazivi polja u validaciji zakucani na srpskom.
- `account_exists` otkriva naloge.

---

## Potvrđene odluke (2026-11-24)

1. **Imena:**
   - folder `external-mobile-app/`;
   - repo `dev-uros/expo-external-ai-setup`;
   - interni folder ostaje `internal-mobile-app/`.

   Svuda (skripta, docs, Makefile, `CLAUDE.md`) mora odmah da se vidi koja je
   aplikacija za eksterne, a koja za interne korisnike.
2. **Tokeni namerno ne ističu.** Svesna odluka za eksternu aplikaciju:
   - bez `expires_at` i bez prune komande;
   - odjava briše token tog uređaja, a brisanje naloga i blokada brišu sve
     tokene.
3. **Prijava je kao u reciklomatu:**
   - server sme da kaže da nalog ne postoji;
   - email: `code` vraća `account_exists`, pa se bez naloga ide na ekran za
     registraciju: email, korisničko ime, opciono ime i prezime, opcioni avatar.
     Posle toga stiže kod i nalog se pravi kad se kod potvrdi;
   - Apple i Google: prvo prijava; 404 vodi na registraciju sa email-om iz
     tokena (samo za čitanje) i korisničkim imenom predloženim iz dela pre `@`,
     bez koda.

   Odvojene rute za prijavu i registraciju; nazive ruta kao u planu (3.2, 3.3)
   prilagoditi tome. Vazi i odeljak 8: bez traženja grešaka po tekstu, sve po
   HTTP statusu.
4. **Profil:**
   - korisničko ime (`username`, obavezno, jedinstveno, bez razlike malih i
     velikih slova);
   - ime i prezime, opciono, uz prekidač „prikaži ime umesto korisničkog
     imena", kao `display_personal_name` u reciklomatu;
   - avatar, opciono.

   Sve može da se menja u podešavanjima. Nema posebnog ekrana za dovršavanje
   profila, jer to radi registracija.
5. **Uslovi:** nema prihvatanja ni `terms_accepted_at`. Podešavanja imaju link
   „Politika privatnosti" iz `EXPO_PUBLIC_PRIVACY_URL`, za sada placeholder
   (kasnije sajt iz site templatea).
6. **Jezik:** podrazumevani je srpski (latinica), a korisnik može da izabere
   engleski. Jezik telefona se ne čita. Ostalo iz 2.4 važi:
   - izbor se učitava pre prvog prikaza;
   - `Accept-Language` na svakom zahtevu;
   - jezik se čuva na nalogu;
   - posle promene jezika osvežavaju se upiti;
   - datumi idu kroz `sr-Latn-RS`;
   - množina kroz i18next.
7. **Admin strana za korisnike aplikacije ulazi u ovaj krug,** u Vue SPA i API
   (lista, pretraga, detalj, uređaji, blokiranje i odblokiranje). Uzor je
   `~/Desktop/Projects/suprabit/reciklomat/web/src/features/mobile-users`
   (samo identitet, bez domenskih kartica) i odgovarajući API u reciklomatu.
8. **Bez `shortcuts`.**
9. **Ekrani posle prijave:**
   - početna sa pozdravom („Ćao, {ime}");
   - podešavanja:
     - izmena profila (korisničko ime, ime i prezime, prekidač, avatar);
     - jezik, tema, notifikacije;
     - politika privatnosti, verzija aplikacije;
     - odjava, brisanje naloga.
10. **Minimalna verzija** je posebna za internu i eksternu aplikaciju (3.6), a
    interni template se prilagođava.
11. **Paketi su isti kao u internom:**
    - Expo SDK 58 paketi, samo preko `npx expo install`;
    - Expo Router, TanStack Query, Zod, Zustand, isti HTTP klijent (fetch), bez
      axiosa;
    - dodaje se samo ono što prijava i jezik traže:
      `@react-native-google-signin/google-signin`, `expo-apple-authentication`,
      `expo-crypto` (nonce), `i18next`, `react-i18next`.
12. **Ispravljaju se svi propusti iz odeljka 8,** osim isticanja tokena (tačka 2).
13. **Obe mobilne aplikacije su opcione** u project-starteru. Ovo menja
    sadašnje ponašanje, u kom je interna podrazumevana uz `--no-mobile`.
    - **Flagovi:** `--with-internal-app` i `--with-external-app`. Bez njih se
      projekat pravi bez mobilnih aplikacija (Laravel + Vue, kao u 90%
      slučajeva). `--no-mobile` se uklanja; ako se ipak prosledi, skripta
      ispiše da je zastareo i šta se sada koristi.
    - **Interaktivni režim** (bez argumenata, dvoklik na `new-project.command`):
      posle imena i destinacije pita posebno „Interna mobilna aplikacija?
      [y/N]" i „Eksterna mobilna aplikacija? [y/N]".
    - **Svaka aplikacija ima svoje:**
      - folder: `internal-mobile-app/` / `external-mobile-app/`;
      - Makefile targete: `internal-app`, `internal-app-ios`,
        `internal-app-android` / `external-app`, `external-app-ios`,
        `external-app-android`;
      - red u root `CLAUDE.md`, `.mcp.json` / skillove i
        `.env.local` sa API adresom.
    - Root `CLAUDE.md`, README projekta i završna poruka skripte („sledeći
      koraci") navode samo izabrane aplikacije.
    - **Backend je uvek isti,** bez obzira na izbor. API za eksterne korisnike
      i admin strana za njih postoje u templateu i kad aplikacija nije izabrana,
      jer se aplikacija može dodati kasnije. Ako je to previše za projekte bez
      mobilnih aplikacija, odlučuje se posle faze 5.
    - Ažurirati README project-startera (tabela flagova, sekcije o mobilnim
      aplikacijama), komentare u `new-project.sh` i `PLAN.md` (oba reda ✅,
      folderi sa novim imenima).
    - Test: napraviti projekat bez aplikacija, samo sa internom, samo sa
      eksternom i sa obe, i proveriti foldere, Makefile, `CLAUDE.md` i
      `.env.local`.

## Ranije otvorena pitanja (rešena gore)

1. Folder `mobile-app/` (u `PLAN.md` stoji `mobile/`, pored `internal-mobile-app/`)?
2. Eksterna aplikacija u novom projektu: opt-in flag ili podrazumevano?
3. Jedan tok za prijavu i registraciju, bez otkrivanja da li nalog postoji —
   ili zadržati reciklomatov `account_exists` i poseban ekran za registraciju?
4. Dovršavanje profila: samo ime? Ime obavezno ili može da se preskoči?
5. Uslovi: implicitno („nastavkom prihvatate") uz upis `terms_accepted_at`,
   ili checkbox?
6. Početni jezik: srpski za sr/hr/bs/me, inače engleski?
7. Tokeni: 90 dana neaktivnosti?
8. Admin strana za korisnike aplikacije: da li u ovom krugu?
9. `shortcuts` (prečice sa ikone aplikacije): zadržati u eksternoj?
