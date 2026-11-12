-- My TCG Vault: sync table. Run once in Supabase → SQL Editor.
create table if not exists public.vault_rows (
  vault      text        not null,
  path       text        not null,
  data       jsonb,
  deleted    boolean     not null default false,
  updated_at timestamptz not null default now(),
  synced_at  timestamptz not null default now(),
  primary key (vault, path)
);
create index if not exists vault_rows_sync on public.vault_rows (vault, synced_at);

-- Only someone who sends the vault's sync code (x-vault header) can read or change its rows.
create or replace function public.vault_key() returns text language sql stable as $$
  select coalesce(current_setting('request.headers', true)::json ->> 'x-vault', '')
$$;
alter table public.vault_rows enable row level security;
drop policy if exists "own vault" on public.vault_rows;
create policy "own vault" on public.vault_rows for all to anon
  using (length(vault) >= 40 and vault = public.vault_key())
  with check (length(vault) >= 40 and vault = public.vault_key());

-- Server time for "what changed since", and an older edit never overwrites a newer one.
create or replace function public.vault_rows_stamp() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and new.updated_at < old.updated_at then
    return old;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end $$;
drop trigger if exists vault_rows_stamp on public.vault_rows;
create trigger vault_rows_stamp before insert or update on public.vault_rows
  for each row execute function public.vault_rows_stamp();

grant select, insert, update, delete on public.vault_rows to anon;
