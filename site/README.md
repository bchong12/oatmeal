# Oatmeal site (Whop blueprint)

The website that sells Oatmeal: landing page, pricing, download, sign-in, account, and the small
API the Mac app signs in with. It runs on Whop's hosting and deploys as a **blueprint**, so anyone can
launch their own Oatmeal business with products and payments already wired.

No database. Whop already knows who has paid, so the site asks Whop each time
(`GET /users/{id}/access/{product}`, cached for two minutes).

## How the pieces fit

```
Mac app ──oatmeal://connect?site=…──▶ remembers your site
Mac app ──opens /api/auth/whop?app=1──▶ Whop sign-in ──▶ oatmeal://signed-in?token=…
Mac app ──GET /api/app/me (Bearer)──▶ site ──▶ Whop: does this user have Pro?
Mac app ──POST /api/app/notes──▶ site ──▶ Claude writes the notes (Pro, optional)
```

- **One Mac app for every site.** The open-source app is the same build for everyone. A site's
  download and account pages have a **Connect** button (`oatmeal://connect?site=…`) that points the
  app at that site. Sign-in, the plan check and Oatmeal AI all go through it.
- **Free** works with no account: recording, on-device transcription, dictation, and notes by the
  user's own Claude Code, Codex or Gemini CLI. Once connected, Free shows the last 30 days of meetings
  (older ones stay on the Mac, locked).
- **Pro** opens every meeting and turns on **Oatmeal AI**: notes written by Claude with the site
  owner's API key, for people without one of those CLIs.

## Deploy

### From the blueprint gallery

1. Open Oatmeal in the Whop blueprint gallery and deploy it (or **Websites › New website › Use a
   blueprint** in your dashboard). Whop copies the site and the products.
2. Open `/setup` on your new site. It lists what's left, with each command filled in for your app.

### From the code

```bash
cd site
npm install
whop apps init --template <oatmeal_app_id> --name "Your Brand"   # or link an app you made
whop apps deploy
```

Then create the products yourself (below) and open `/setup`.

## Products

Plans are matched to your store's products by title, so copies of the blueprint sell through their
own products. Keep the plan's name in each product title.

| Product title contains | Monthly | Yearly | Unlocks |
|---|---|---|---|
| Free | $0 | | nothing (optional: lets free users "buy" so you get their email) |
| Pro | $14 | $144 | every meeting, Oatmeal AI |
| Business | $35 / person | $348 | shown as coming soon |

Give a paid product two pricing options (renewing every 30 and every 365 days) for the yearly toggle.
Prices and wording live in `oatmeal.config.ts`. To pin a plan to a product, set `PLAN_PRO_PRODUCT_ID`
and `PLAN_PRO_URL` (they win over the title lookup).

## Secrets

Set with the Whop CLI (`whop apps secrets set --secret NAME=value`), then redeploy.

| Secret | Needed | What it does |
|---|---|---|
| `SESSION_SECRET` | yes | Signs sign-in cookies and the Mac app's tokens. `$(openssl rand -hex 32)` |
| `ANTHROPIC_API_KEY` | for Oatmeal AI | Pro members get notes written by Claude (`claude-opus-5-5`), billed to this key |
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
