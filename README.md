# Central Prisma — Plataforma de Aulas

Central de implantação do método Prisma: aulas, trilhas, scripts, checklists, PGM,
acompanhamento de 90 dias, gestão de empresas/acessos e métricas de uso.

Site de **página única** (`index.html`, tudo embutido — HTML/CSS/JS inline).
Os vídeos ficam no YouTube (embutidos), então o site é leve.

---

## Como está hospedado

- **Frontend (este repositório):** site estático servido por nginx via `Dockerfile`,
  publicado no **EasyPanel** a partir deste repositório Git.
- **Backend (próxima fase):** **Supabase** (login por empresa/usuário, permissões, métricas).
  Ainda não conectado — o login atual é de demonstração.

## Deploy (EasyPanel)

1. App novo no EasyPanel → Source = este repositório GitHub → branch `main`.
2. Build = **Dockerfile** (detectado automaticamente).
3. Deploy. Ativar **auto-deploy** para republicar a cada `push`.

Para atualizar o site: **commitar o `index.html` novo → EasyPanel republica.**

## Acesso de demonstração (preview — trocar quando o Supabase entrar)

- Admin (Prisma): `admin@prisma.com` / `prisma123`
- Cliente: `ferraco@cliente.com` / `cliente123`

> ⚠️ Estas senhas são só de demonstração (validadas no navegador).
> A segurança real vem na fase do Supabase (Auth + RLS).

## Estrutura

```
.
├── index.html      # a plataforma inteira
├── Dockerfile      # nginx servindo o site (deploy EasyPanel)
├── .dockerignore
├── .gitignore
└── README.md
```
