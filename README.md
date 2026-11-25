# Bacheca lavoro — Server

Server REST in Dart per l'[app Bacheca lavoro](https://github.com/amedeonapoli25/bacheca-lavoro).
Gestisce registrazione delle aziende,
login tramite email e password, consultazione del proprio account, logout e annunci
di lavoro. La bacheca e il dettaglio degli annunci sono pubblici; la pubblicazione
e la consultazione dei propri annunci richiedono l'accesso aziendale.
I candidati inviano generalità e curriculum senza registrazione.
L'azienda proprietaria consulta le candidature ricevute e apre i relativi PDF
tramite endpoint autenticati.
La registrazione crea l'account; il login viene eseguito separatamente.

## Requisiti e avvio

Richiede Dart 3.13.5 o compatibile. Dalla cartella del server:

```bash
dart pub get
dart run bin/server.dart
```

Il server ascolta sulla porta 8080 e stampa gli indirizzi da usare nell'app.
Per verificare che sia avviato, aprire `http://127.0.0.1:8080/api/health` sul Mac.
Per un telefono fisico usare l'indirizzo del Mac nella rete locale; Mac e telefono
devono potersi raggiungere sulla rete e il server deve restare acceso.

Le variabili d'ambiente `PORT` e `DATA_DIR` permettono di cambiare porta e cartella
dei dati. I valori predefiniti sono `8080` e `data` nella directory di avvio.

## Dati e autenticazione

Gli account sono conservati in `data/companies.json`, creato alla prima registrazione.
Le scritture sono serializzate e passano da un file temporaneo. Il file contiene
hash PBKDF2 e sale casuale per le password; le API restituiscono soltanto i dati pubblici.
I dati locali sono esclusi da Git.

Il login emette un token opaco da inviare come `Authorization: Bearer <token>`.
I token sono in memoria: il logout li revoca e il riavvio del server richiede un
nuovo login. Gli account restano disponibili dopo il riavvio.

| Metodo | Endpoint | Accesso |
| --- | --- | --- |
| GET | `/api/health` | Pubblico |
| POST | `/api/auth/register` | Pubblico; JSON con `name`, `email`, `password` |
| POST | `/api/auth/login` | Pubblico; JSON con `email`, `password` |
| GET | `/api/auth/me` | Token richiesto |
| POST | `/api/auth/logout` | Token richiesto |
| GET | `/api/jobs` | Pubblico; annunci dal più recente |
| GET | `/api/jobs/ID` | Pubblico; dettaglio dell'annuncio |
| POST | `/api/jobs` | Token richiesto; JSON con `title` e `description` |
| GET | `/api/company/jobs` | Token richiesto; annunci della propria azienda |
| POST | `/api/jobs/ID/applications` | Pubblico; form multipart con dati e PDF |
| GET | `/api/company/jobs/ID/applications` | Token dell'azienda proprietaria |
| GET | `/api/company/applications/ID` | Token dell'azienda proprietaria |
| GET | `/api/company/applications/ID/cv` | Token dell'azienda proprietaria; PDF binario |

Il nome azienda deve avere da 2 a 80 caratteri. L'email deve essere valida e univoca,
senza distinzione tra maiuscole e minuscole. La password deve avere da 8 a 128 caratteri.
Gli errori sono risposte JSON con un campo `error`.

Gli annunci sono conservati in `data/jobs.json`. Il titolo deve avere da 1 a 120
caratteri e la descrizione da 1 a 5000 caratteri, dopo la rimozione degli spazi
iniziali e finali. Il proprietario è sempre l'azienda identificata dal token;
un eventuale `companyId` nel corpo della richiesta non modifica l'assegnazione.
Le risposte pubbliche includono il nome dell'azienda, senza email o dati di accesso.

## Candidature

L'endpoint di candidatura richiede i campi multipart `firstName`, `lastName`, `email`
e `submissionId`, più un solo file nella parte `cv`. Nome e cognome devono avere
da 1 a 80 caratteri. `submissionId` è un codice casuale di 16-64 caratteri composto
da lettere, cifre, trattino o underscore, generato dall'app per riconoscere i ritentativi.

Il file deve avere estensione PDF, intestazione `%PDF-`, marcatore finale `%%EOF` e
dimensione da 1 byte a 5 MiB. Si controllano anche il limite dell'intera richiesta
e la chiusura del messaggio multipart. Non viene eseguita una verifica completa
della struttura interna del documento PDF.

I dati sono salvati in `data/applications.json`; i PDF sono in `data/curricula`, con
nomi casuali generati dal server. L'originale viene conservato come informazione,
senza usarlo come percorso sul disco. Se il JSON non può essere salvato, il PDF
appena scritto viene rimosso. La risposta `201` contiene solo `id`, `jobId` e `createdAt`.

Ripetere lo stesso invio restituisce la stessa ricevuta senza creare doppioni.
Riutilizzare il codice con dati differenti restituisce `409`. Invii distinti con
la stessa email sono ammessi. Un'azienda con token valido riceve `403` se tenta
di candidarsi. Non sono esposti endpoint pubblici per elencare candidature o scaricare PDF.

## Consultazione riservata

I tre endpoint sotto `/api/company` controllano il token e la proprietà
dell'annuncio per ogni richiesta. Senza una sessione valida restituiscono `401`;
risorse inesistenti o appartenenti ad altre aziende restituiscono `404`.
L'elenco può essere vuoto. Elenco e dettaglio includono i dati del candidato,
il titolo dell'annuncio e nome e dimensione del PDF, senza percorsi interni,
identificativi d'invio o impronte dei dati.

L'endpoint `/cv` restituisce byte `application/pdf`, con `Cache-Control: no-store`.
Un file mancante restituisce `404`; un file alterato o incompleto restituisce `409`.
Il logout revoca il token anche per questi endpoint. Il riavvio conserva dati e PDF,
ma richiede un nuovo login perché le sessioni sono in memoria.

## Verifiche

```bash
dart analyze
dart test
```

I test usano porte assegnate automaticamente e cartelle temporanee separate dai dati dell'app.
