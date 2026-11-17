# Oatmeal site (Whop blueprint)

Oatmeal's website: landing page, download, sign-in, account, and the small API the Mac app signs in
with. It runs on Whop's hosting and deploys as a **blueprint**, so anyone can put up their own copy.

Oatmeal is free: there are no plans, prices or paid features, and no database.

## How the pieces fit

```
Mac app ──oatmeal://connect?site=…──▶ remembers your site
Mac app ──opens /api/auth/whop?app=1──▶ Whop sign-in ──▶ oatmeal://signed-in?token=…
Mac app ──GET /api/app/me (Bearer)──▶ site: who's signed in
```

- **One Mac app for every site.** The open-source app is the same build for everyone. A site's
  download and account pages have a **Connect** button (`oatmeal://connect?site=…`) that points the
  app at that site, and sign-in goes through it.
- **Everything works without an account:** recording, on-device transcription, dictation, screen
  captures, and notes by the user's own Claude Code, Codex or Gemini CLI.

## Deploy

### From the blueprint gallery

1. Open Oatmeal in the Whop blueprint gallery and deploy it (or **Websites › New website › Use a
   blueprint** in your dashboard). Whop copies the site.
2. Open `/setup` on your new site. It lists what's left, with each command filled in for your app.

### From the code

```bash
cd site
npm install
whop apps init --template <oatmeal_app_id> --name "Your Brand"   # or link an app you made
whop apps deploy
```

Then open `/setup`.

## Secrets

Set with the Whop CLI (`whop apps secrets set --secret NAME=value`), then redeploy.

| Secret | Needed | What it does |
|---|---|---|
| `SESSION_SECRET` | yes | Signs sign-in cookies and the Mac app's tokens. `$(openssl rand -hex 32)` |
| `DOWNLOAD_URL` | no | Your own signed `.dmg`. Default: the open-source app's latest GitHub release |
| `BRAND_NAME`, `BRAND_TAGLINE`, `BRAND_COMPANY`, `BRAND_SUPPORT_EMAIL` | no | Rename the site without code |
| `WHOP_CLIENT_SECRET` | if your app shows one | Used for the sign-in code exchange |

Whop hosting sets `APP_ID`, `WHOP_ACCOUNT_ID` and `WHOP_API_ORIGIN` itself, and its proxy attaches the
API key, so there's no Whop key to set. The site registers its own sign-in callback the first time
someone opens `/setup` or signs in.

## Local development

```bash
npm install
printf 'SESSION_SECRET=dev\n' > .dev.vars
npm run dev          # http://localhost:3000
npm test             # unit tests
npm run typecheck
```

Sign-in needs a Whop app, so locally it stays off; everything else works. To try the Mac app against
your local site, open `oatmeal://connect?site=http://localhost:3000`.
