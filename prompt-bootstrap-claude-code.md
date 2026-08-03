# Prompt di bootstrap — Fase 1

Copia tutto il blocco qui sotto in Claude Code CLI, dentro una cartella vuota.
Metti prima `V1__initial_schema.sql` nella stessa cartella: il prompt lo riferisce.

---

Sto costruendo un'app personale di analisi cash flow e proposte di investimento,
da deployare su un mini PC via Docker Compose. Il mio obiettivo primario è
**imparare Quarkus**, non avere l'app finita: a settembre inizio un progetto di
lavoro in Quarkus e Vue e questo è il mio training.

Per questo motivo, lavora così:

1. **Prima di scrivere qualsiasi codice, presentami un piano** con la struttura
   dei package, le classi che intendi creare e le estensioni Quarkus scelte.
   Fermati e aspetta la mia conferma.
2. Poi procedi a **piccoli step verificabili**, un'area funzionale per volta.
   Dopo ogni step fermati, dimmi cosa hai fatto e cosa dovrei controllare.
3. Quando usi una feature specifica di Quarkus (Panache, Dev Services, CDI,
   `@Transactional`, RESTEasy Reactive) **aggiungi due righe di spiegazione** su
   cosa fa e quale sarebbe l'alternativa in Spring Boot o JPA puro. Sono le cose
   che devo imparare.
4. Non scrivere commenti ovvi nel codice. Commenta solo le decisioni non banali.

## Scope della Fase 1 — cosa fare

Solo il backend. Import manuale dei movimenti bancari, categorizzazione,
calcolo del cash flow. Endpoint testabili con curl.

Endpoint da esporre sotto `/api`:

- `POST /accounts`, `GET /accounts` — anagrafica conti
- `GET /categories`, `POST /categories`, `POST /categories/seed`
  (seed = insieme di default sensato per l'Italia: stipendio, affitto/mutuo,
  utenze, spesa, trasporti, ristoranti, salute, giroconti, investimenti)
- `POST /imports` — upload multipart di un file estratto conto + `accountId`.
  Risponde con un riepilogo: righe lette, importate, scartate come duplicate,
  righe in errore con motivo.
- `GET /transactions` — filtri `from`, `to`, `categoryId`, `uncategorized`,
  paginato
- `PATCH /transactions/{id}/category` — ricategorizzazione manuale
- `GET /cashflow/summary?from&to` — entrate, spese fisse, spese variabili,
  netto e surplus investibile

## Scope della Fase 1 — cosa NON fare

Non implementare, nemmeno in stub: frontend, autenticazione, dati di mercato,
motore di allocazione, tabelle `instrument`/`trade`/`proposal` (esistono nello
schema ma restano vuote in questa fase), chiamate a LLM, native image.

## Stack

- Java 21, Maven, Quarkus stabile più recente (verifica la versione, non
  assumerla)
- Estensioni: `quarkus-rest-jackson`, `quarkus-hibernate-orm-panache`,
  `quarkus-jdbc-postgresql`, `quarkus-flyway`, `quarkus-hibernate-validator`,
  `quarkus-smallrye-openapi`, `quarkus-junit5`, `quarkus-rest-assured`
- Apache POI per XLS/XLSX, Apache Commons CSV per il CSV
- Postgres 16 via Dev Services in sviluppo, Docker Compose per il deploy

## Database

**Usa il file `V1__initial_schema.sql` che trovi in questa cartella così com'è.**
Spostalo in `src/main/resources/db/migration/`. Non generare lo schema da
Hibernate: `quarkus.hibernate-orm.database.generation=none` e Flyway come unica
fonte di verità. Le entità Panache devono mappare quello schema, non il
contrario. Se pensi che lo schema abbia un problema, segnalamelo invece di
modificarlo di tua iniziativa.

## Parsing degli estratti conto

Definisci un'astrazione `StatementParser` con due implementazioni CDI
selezionate a runtime in base al file:

- `CsvStatementParser` — implementalo completamente
- `XlsStatementParser` — **lascialo volutamente minimale**: struttura della
  classe, rilevamento dinamico della riga di header cercando una cella che
  contenga "data", e un TODO chiaro. Non conosco ancora il layout esatto
  dell'export della mia banca, lo completeremo insieme dopo.

Requisiti del parsing, tutti importanti:

- Rileva il formato reale dal contenuto, non dall'estensione. Alcune banche
  italiane esportano HTML o CSV con estensione `.xls`: se i primi byte
  contengono `<html` o `<table`, il file va trattato di conseguenza e non
  passato a POI.
- Gli importi arrivano come stringhe in formato italiano (`1.234,56`) o su due
  colonne separate entrate/uscite. Parsa con `Locale.ITALY` e converti sempre
  in `BigDecimal`. **Mai `double` o `float` su un importo, in nessun punto del
  codice.**
- Le righe di intestazione e di piede (intestatario, IBAN, saldi, totali) vanno
  ignorate.
- Una riga malformata non deve interrompere l'import: raccogli l'errore,
  continua, restituiscilo nel riepilogo.

## Deduplica

È il requisito più importante dell'import, perché reimporterò periodi
sovrapposti. Per ogni riga calcola `natural_key` = SHA-256 di
`value_date | amount | descrizione normalizzata | accountId | occurrence`, dove
la descrizione normalizzata è trim, lowercase e whitespace collassato, e
`occurrence` è un contatore progressivo per gestire movimenti realmente identici
nello stesso giorno. L'unique constraint su `(account_id, natural_key)` esiste
già: gestisci il conflitto come skip silenzioso, non come errore.

## Categorizzazione

Motore a regole, tabella `categorization_rule`, valutate per `priority`
crescente, prima che matcha vince. Se nessuna regola matcha, la transazione
resta con `category_id` null e va recuperata da
`GET /transactions?uncategorized=true`. Nessun LLM in questa fase.

## Cash flow

Il calcolo del surplus deve escludere le categorie con `kind` `TRANSFER` e
`INVESTMENT`. Un giroconto verso un mio conto deposito compare come uscita
sull'estratto conto ma non è una spesa: se lo conti, il surplus è sbagliato per
costruzione. Questo è il requisito di dominio che conta più di tutti gli altri.

## Convenzioni

- Record Java immutabili per i DTO. Entità e DTO separati, mai entità esposte
  negli endpoint.
- Pattern repository con `PanacheRepository`, non active record: voglio vedere
  la separazione.
- Bean Validation sugli input, `@Transactional` sui service, non sui resource.
- Gestione errori centralizzata con `ExceptionMapper` e risposte in formato
  Problem Details (RFC 9457).

## Test

Almeno: un test di parsing su un CSV di esempio che metti in
`src/test/resources`, un test che verifica che il reimport dello stesso file non
crei duplicati, e un test sul calcolo del surplus che dimostra che i giroconti
sono esclusi. RestAssured per gli endpoint, Dev Services per il database.

## Deliverable finale

Oltre al codice: un `docker-compose.yml` per il deploy (app + Postgres, con
volume persistente), un `README.md` con i comandi per partire, e un `CLAUDE.md`
che riassuma le convenzioni di questo progetto e le regole di lavoro qui sopra,
così restano valide nelle prossime sessioni.

Comincia dal piano.
