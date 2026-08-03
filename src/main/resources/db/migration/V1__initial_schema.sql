-- V1__initial_schema.sql
-- Schema iniziale: cash flow + portafoglio.
-- Convenzioni:
--   * importi sempre numeric(15,2), mai float
--   * enum come text + CHECK (piu facili da evolvere dei native enum di Postgres,
--     e compatibili con @Enumerated(EnumType.STRING) su Panache)
--   * timestamptz per tutto cio che e un istante, date per le date contabili

create table account (
    id            bigserial primary key,
    name          text        not null,
    bank_name     text,
    iban          text unique,
    kind          text        not null check (kind in ('CHECKING', 'SAVINGS', 'CARD', 'BROKER')),
    currency      char(3)     not null default 'EUR',
    active        boolean     not null default true,
    created_at    timestamptz not null default now()
);

create table category (
    id            bigserial primary key,
    parent_id     bigint      references category (id) on delete set null,
    name          text        not null,
    -- kind guida il motore di cash flow: TRANSFER e INVESTMENT sono esclusi
    -- dal calcolo delle spese, altrimenti i giroconti falsano il surplus
    kind          text        not null check (kind in ('INCOME', 'FIXED_EXPENSE', 'VARIABLE_EXPENSE', 'TRANSFER', 'INVESTMENT')),
    created_at    timestamptz not null default now(),
    unique (parent_id, name)
);

-- Ogni import e tracciato: permette di annullare un batch sbagliato
create table import_batch (
    id             bigserial primary key,
    account_id     bigint      not null references account (id),
    source_name    text        not null,
    source_format  text        not null check (source_format in ('XLS', 'XLSX', 'CSV', 'PDF', 'API')),
    file_sha256    char(64)    not null,
    period_start   date,
    period_end     date,
    row_count      integer     not null default 0,
    imported_at    timestamptz not null default now()
);

create table transaction (
    id                  bigserial primary key,
    account_id          bigint        not null references account (id),
    import_batch_id     bigint        references import_batch (id) on delete set null,
    booking_date        date          not null,
    value_date          date          not null,
    amount              numeric(15,2) not null check (amount <> 0),
    currency            char(3)       not null default 'EUR',
    -- descrizione originale mai modificata: serve per rigirare la categorizzazione
    raw_description     text          not null,
    counterparty        text,
    category_id         bigint        references category (id) on delete set null,
    category_source     text          check (category_source in ('RULE', 'LLM', 'MANUAL')),
    category_confidence numeric(3,2)  check (category_confidence between 0 and 1),
    -- hash(value_date + amount + descrizione normalizzata + account + occurrence)
    natural_key         char(64)      not null,
    created_at          timestamptz   not null default now(),
    constraint uq_transaction_natural_key unique (account_id, natural_key)
);

create index idx_transaction_value_date on transaction (value_date desc);
create index idx_transaction_category on transaction (category_id) where category_id is not null;
create index idx_transaction_uncategorized on transaction (account_id) where category_id is null;

create table categorization_rule (
    id            bigserial primary key,
    priority      integer     not null default 100,
    match_field   text        not null check (match_field in ('RAW_DESCRIPTION', 'COUNTERPARTY', 'AMOUNT')),
    pattern       text        not null,
    category_id   bigint      not null references category (id) on delete cascade,
    active        boolean     not null default true,
    created_at    timestamptz not null default now()
);

create index idx_rule_active on categorization_rule (priority) where active;

create table instrument (
    id            bigserial primary key,
    isin          char(12) unique,
    ticker        text,
    name          text          not null,
    asset_class   text          not null check (asset_class in ('EQUITY', 'BOND', 'COMMODITY', 'REIT', 'CASH', 'OTHER')),
    currency      char(3)       not null default 'EUR',
    ter           numeric(5,4),
    ucits         boolean       not null default true,
    created_at    timestamptz   not null default now()
);

-- Le posizioni si derivano dai trade, non si memorizzano: serve per il calcolo
-- delle plusvalenze e per lo zainetto fiscale
create table trade (
    id            bigserial primary key,
    account_id    bigint        not null references account (id),
    instrument_id bigint        not null references instrument (id),
    side          text          not null check (side in ('BUY', 'SELL')),
    trade_date    date          not null,
    quantity      numeric(18,6) not null check (quantity > 0),
    price         numeric(15,4) not null check (price > 0),
    fees          numeric(15,2) not null default 0,
    tax_withheld  numeric(15,2) not null default 0,
    created_at    timestamptz   not null default now()
);

create index idx_trade_instrument_date on trade (instrument_id, trade_date);

create table instrument_price (
    instrument_id bigint        not null references instrument (id) on delete cascade,
    price_date    date          not null,
    close         numeric(15,4) not null,
    primary key (instrument_id, price_date)
);

-- Allocazione target versionata: valid_from permette di rivedere la strategia
-- senza perdere lo storico delle decisioni
create table allocation_target (
    id            bigserial primary key,
    asset_class   text          not null check (asset_class in ('EQUITY', 'BOND', 'COMMODITY', 'REIT', 'CASH', 'OTHER')),
    target_weight numeric(5,4)  not null check (target_weight between 0 and 1),
    band_pct      numeric(5,4)  not null default 0.05,
    valid_from    date          not null,
    created_at    timestamptz   not null default now(),
    unique (asset_class, valid_from)
);

-- Le proposte sono sempre suggerimenti: nessuna esecuzione automatica
create table proposal (
    id            bigserial primary key,
    generated_at  timestamptz   not null default now(),
    instrument_id bigint        references instrument (id),
    action        text          not null check (action in ('BUY', 'SELL', 'HOLD', 'REBALANCE')),
    amount        numeric(15,2),
    rationale     text          not null,
    status        text          not null default 'PENDING' check (status in ('PENDING', 'ACCEPTED', 'REJECTED', 'EXPIRED'))
);

create index idx_proposal_pending on proposal (generated_at desc) where status = 'PENDING';
