-- =====================================================================
-- CENTRAL PRISMA — Schema + Segurança (Supabase / Postgres)
-- Cole tudo no SQL Editor do projeto e clique em "Run".
-- Seguro de rodar mais de uma vez (idempotente no que dá).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- ENUMs ----------
do $$ begin
  create type papel_global as enum ('admin','client');
exception when duplicate_object then null; end $$;

do $$ begin
  create type papel_membro as enum ('gestor','vendedor','viewer');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_aula as enum ('disponivel','producao','bloqueado');
exception when duplicate_object then null; end $$;

-- =====================================================================
-- PROFILES (1:1 com auth.users)
-- =====================================================================
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nome        text,
  email       text,
  papel       papel_global not null default 'client',
  created_at  timestamptz not null default now()
);

-- cria o profile automaticamente quando nasce um usuário no Auth
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nome, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', new.email), new.email)
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- helper: o usuário atual é admin da Prisma?
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.papel = 'admin'
  );
$$;

-- =====================================================================
-- EMPRESAS (clientes) e MEMBROS
-- =====================================================================
create table if not exists public.empresas (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.empresa_membros (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  papel       papel_membro not null default 'vendedor',
  created_at  timestamptz not null default now(),
  unique (empresa_id, user_id)
);

-- helper: o usuário atual pertence a esta empresa?
create or replace function public.is_empresa_member(_empresa_id uuid)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.empresa_membros m
    where m.empresa_id = _empresa_id and m.user_id = auth.uid()
  );
$$;

-- helper: empresas do usuário atual
create or replace function public.minhas_empresas()
returns setof uuid
language sql
security definer
set search_path = ''
stable
as $$
  select empresa_id from public.empresa_membros where user_id = auth.uid();
$$;

-- =====================================================================
-- CONTEÚDO (global): TRILHAS, AULAS, MATERIAIS
-- =====================================================================
create table if not exists public.trilhas (
  id          text primary key,
  nome        text not null,
  sup         text,
  descricao   text,
  cover_url   text,
  grad        text,
  ic          text,
  ordem       int not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.aulas (
  id          uuid primary key default gen_random_uuid(),
  titulo      text not null,
  modulo      text,
  descricao   text,
  resumo      text,
  dur         text,
  area        text,
  status      status_aula not null default 'disponivel',
  tag         text,
  yt          text,
  ordem       int not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.trilha_aulas (
  trilha_id   text not null references public.trilhas(id) on delete cascade,
  aula_id     uuid not null references public.aulas(id) on delete cascade,
  ordem       int not null default 0,
  primary key (trilha_id, aula_id)
);

create table if not exists public.materiais (
  id          uuid primary key default gen_random_uuid(),
  nome        text not null,
  url         text not null,
  descricao   text,
  aula_id     uuid references public.aulas(id) on delete cascade, -- null = material global
  created_at  timestamptz not null default now()
);

-- =====================================================================
-- PROGRESSO e EVENTOS (métricas)
-- =====================================================================
create table if not exists public.progresso (
  user_id      uuid not null references auth.users(id) on delete cascade,
  aula_id      uuid not null references public.aulas(id) on delete cascade,
  concluido_em timestamptz not null default now(),
  primary key (user_id, aula_id)
);

create table if not exists public.eventos (
  id          bigint generated by default as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  tipo        text not null,           -- 'acesso' | 'watch' | 'tempo'
  aula_id     uuid references public.aulas(id) on delete set null,
  ms          int,                     -- duração em ms (watch/tempo)
  created_at  timestamptz not null default now()
);

-- =====================================================================
-- ÍNDICES (RLS + consultas rápidas)
-- =====================================================================
create index if not exists idx_empresa_membros_user     on public.empresa_membros(user_id);
create index if not exists idx_empresa_membros_empresa  on public.empresa_membros(empresa_id);
create index if not exists idx_trilha_aulas_trilha      on public.trilha_aulas(trilha_id);
create index if not exists idx_materiais_aula           on public.materiais(aula_id);
create index if not exists idx_progresso_user           on public.progresso(user_id);
create index if not exists idx_eventos_user             on public.eventos(user_id);
create index if not exists idx_eventos_created          on public.eventos(created_at desc);

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
alter table public.profiles         enable row level security;
alter table public.empresas         enable row level security;
alter table public.empresa_membros  enable row level security;
alter table public.trilhas          enable row level security;
alter table public.aulas            enable row level security;
alter table public.trilha_aulas     enable row level security;
alter table public.materiais        enable row level security;
alter table public.progresso        enable row level security;
alter table public.eventos          enable row level security;

-- ---------- PROFILES ----------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using ( id = auth.uid() or public.is_admin() );
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated
  using ( id = auth.uid() or public.is_admin() )
  with check ( id = auth.uid() or public.is_admin() );

-- ---------- EMPRESAS ----------
drop policy if exists empresas_select on public.empresas;
create policy empresas_select on public.empresas for select to authenticated
  using ( public.is_admin() or public.is_empresa_member(id) );
drop policy if exists empresas_admin_write on public.empresas;
create policy empresas_admin_write on public.empresas for all to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );

-- ---------- EMPRESA_MEMBROS ----------
drop policy if exists membros_select on public.empresa_membros;
create policy membros_select on public.empresa_membros for select to authenticated
  using ( public.is_admin() or user_id = auth.uid() or public.is_empresa_member(empresa_id) );
drop policy if exists membros_admin_write on public.empresa_membros;
create policy membros_admin_write on public.empresa_membros for all to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );

-- ---------- CONTEÚDO (trilhas/aulas/trilha_aulas/materiais): todos leem, admin escreve ----------
drop policy if exists trilhas_read on public.trilhas;
create policy trilhas_read on public.trilhas for select to authenticated using ( true );
drop policy if exists trilhas_admin on public.trilhas;
create policy trilhas_admin on public.trilhas for all to authenticated using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists aulas_read on public.aulas;
create policy aulas_read on public.aulas for select to authenticated using ( true );
drop policy if exists aulas_admin on public.aulas;
create policy aulas_admin on public.aulas for all to authenticated using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists trilha_aulas_read on public.trilha_aulas;
create policy trilha_aulas_read on public.trilha_aulas for select to authenticated using ( true );
drop policy if exists trilha_aulas_admin on public.trilha_aulas;
create policy trilha_aulas_admin on public.trilha_aulas for all to authenticated using ( public.is_admin() ) with check ( public.is_admin() );

drop policy if exists materiais_read on public.materiais;
create policy materiais_read on public.materiais for select to authenticated using ( true );
drop policy if exists materiais_admin on public.materiais;
create policy materiais_admin on public.materiais for all to authenticated using ( public.is_admin() ) with check ( public.is_admin() );

-- ---------- PROGRESSO (cada um o seu; admin lê tudo) ----------
drop policy if exists progresso_own on public.progresso;
create policy progresso_own on public.progresso for all to authenticated
  using ( user_id = auth.uid() or public.is_admin() )
  with check ( user_id = auth.uid() );

-- ---------- EVENTOS (usuário insere o seu; admin lê tudo) ----------
drop policy if exists eventos_insert_own on public.eventos;
create policy eventos_insert_own on public.eventos for insert to authenticated
  with check ( user_id = auth.uid() );
drop policy if exists eventos_select on public.eventos;
create policy eventos_select on public.eventos for select to authenticated
  using ( public.is_admin() or user_id = auth.uid() );

-- =====================================================================
-- SEED do conteúdo inicial (trilhas) — pode editar/adicionar depois pelo painel
-- =====================================================================
insert into public.trilhas (id, nome, sup, descricao, grad, ic, ordem) values
  ('inicio','Aqui','Comece por','O panorama do método e como usar a plataforma.', 'radial-gradient(120% 85% at 72% 8%, rgba(255,77,109,.45), transparent 58%), linear-gradient(158deg,#17121c,#0a0910)','<path d="M5 3v18"/><path d="M5 4h11l-2 3 2 3H5"/>',1),
  ('sondagem','Sondagem','Trilha de','Saudação que engaja e os 4 pilares antes do preço.', 'radial-gradient(120% 85% at 72% 8%, rgba(255,77,109,.5), transparent 58%), linear-gradient(158deg,#17121c,#0a0910)','<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',2),
  ('followup','Follow-up','Trilha de','A régua D+1 a D+7 e como reativar o lead que sumiu.', 'radial-gradient(120% 85% at 72% 8%, rgba(232,155,60,.45), transparent 58%), linear-gradient(158deg,#17121c,#0a0910)','<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/>',3),
  ('fechamento','Fechamento','Trilha de','Contornar objeções e pedir a venda sem medo.', 'radial-gradient(120% 85% at 72% 8%, rgba(111,230,158,.42), transparent 58%), linear-gradient(158deg,#17121c,#0a0910)','<circle cx="12" cy="12" r="9"/><path d="m8.5 12 2.5 2.5 5-5"/>',4),
  ('trafego','Tráfego','Anúncios &','Oferta, criativos e roteiros que trazem lead qualificado.', 'radial-gradient(120% 85% at 72% 8%, rgba(255,77,109,.48), transparent 58%), linear-gradient(158deg,#17121c,#0a0910)','<path d="M3 11v2a1 1 0 0 0 1 1h2l4 4V6L6 10H4a1 1 0 0 0-1 1z"/><path d="M14 8a4 4 0 0 1 0 8"/>',5),
  ('indicadores','Indicadores','Leitura de','Ler a PGM, os 12 KPIs e achar o gargalo da semana.', 'radial-gradient(120% 85% at 72% 8%, rgba(111,230,158,.4), transparent 58%), linear-gradient(158deg,#17121c,#0a0910)','<path d="M3 20h18"/><rect x="5" y="11" width="3.2" height="7"/><rect x="10.4" y="7" width="3.2" height="11"/><rect x="15.8" y="4" width="3.2" height="14"/>',6)
on conflict (id) do nothing;

-- =====================================================================
-- JORNADA — "onde você está" (status por empresa)
-- Etapas de execução (diagnostico/oferta/anuncios): SÓ admin marca.
-- Etapas de treino (treino-wpp/scripts/acompanha): o CLIENTE marca.
-- Sem esta tabela, o app funciona só no navegador (não compartilha).
-- =====================================================================
create table if not exists public.jornada (
  empresa_id  uuid not null references public.empresas(id) on delete cascade,
  step_key    text not null,
  done        boolean not null default false,
  updated_by  uuid references auth.users(id) on delete set null,
  updated_at  timestamptz not null default now(),
  primary key (empresa_id, step_key)
);
alter table public.jornada enable row level security;

-- lê quem é admin ou membro da empresa
drop policy if exists jornada_select on public.jornada;
create policy jornada_select on public.jornada for select to authenticated
  using ( public.is_admin() or public.is_empresa_member(empresa_id) );

-- admin escreve qualquer etapa
drop policy if exists jornada_write_admin on public.jornada;
create policy jornada_write_admin on public.jornada for all to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );

-- membro escreve SÓ as etapas de treino, e só da própria empresa
drop policy if exists jornada_write_membro on public.jornada;
create policy jornada_write_membro on public.jornada for all to authenticated
  using ( public.is_empresa_member(empresa_id) and step_key in ('treino-wpp','scripts','acompanha') )
  with check ( public.is_empresa_member(empresa_id) and step_key in ('treino-wpp','scripts','acompanha') );

-- =====================================================================
-- TRILHAS LIBERADAS POR EMPRESA (controle de acesso por cliente)
-- Sem isto, o app funciona só no navegador do admin (não aplica p/ cliente).
-- =====================================================================
alter table public.empresas add column if not exists trilhas_restrito boolean not null default false;

create table if not exists public.empresa_trilhas (
  empresa_id uuid not null references public.empresas(id) on delete cascade,
  trilha_id  text not null references public.trilhas(id) on delete cascade,
  primary key (empresa_id, trilha_id)
);
alter table public.empresa_trilhas enable row level security;

drop policy if exists empresa_trilhas_select on public.empresa_trilhas;
create policy empresa_trilhas_select on public.empresa_trilhas for select to authenticated
  using ( public.is_admin() or public.is_empresa_member(empresa_id) );

drop policy if exists empresa_trilhas_admin on public.empresa_trilhas;
create policy empresa_trilhas_admin on public.empresa_trilhas for all to authenticated
  using ( public.is_admin() ) with check ( public.is_admin() );

-- =====================================================================
-- FIM.
-- =====================================================================
