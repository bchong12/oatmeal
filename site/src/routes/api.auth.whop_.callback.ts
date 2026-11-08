import { createFileRoute } from '@tanstack/react-router'
import { brandFrom } from '#/lib/brand'
import { env } from '#/lib/env'
import { baseUrl, cookie, readCookie, redirect } from '#/lib/server/http'
import { SESSION_COOKIE, SESSION_DAYS, signSession } from '#/lib/session'
import { whopExchangeCode } from '#/lib/whop'

export const Route = createFileRoute('/api/auth/whop_/callback')({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const url = new URL(request.url)
        const [state, verifier, kind] = (readCookie(request, 'oat_oauth') ?? '').split('.')
        const clear = cookie('oat_oauth', '', 0)
        if (!state || state !== url.searchParams.get('state') || !verifier) return redirect('/login?error=expired', [clear])
        const code = url.searchParams.get('code')
        if (!code) return redirect('/login?error=denied', [clear])

        const base = baseUrl(request, env.appUrl)
        const user = await whopExchangeCode({
          clientId: env.whopAppId,
          clientSecret: env.whopClientSecret,
          redirectUri: `${base}/api/auth/whop/callback`,
          code,
          codeVerifier: verifier,
        })
        const who = { whopUserId: user.id, name: user.name, email: user.email }

        if (kind === 'app') {
          const token = await signSession({ ...who, kind: 'app' }, env.sessionSecret)
          return handBackToApp(token, base, brandFrom(env.read).name, [clear])
        }
        const token = await signSession({ ...who, kind: 'web' }, env.sessionSecret)
        return redirect('/account', [clear, cookie(SESSION_COOKIE, token, SESSION_DAYS * 86_400)])
      },
    },
  },
})

/** A small page that opens the Mac app with its token, with a button in case the browser asks first. */
function handBackToApp(token: string, site: string, brand: string, cookies: string[]): Response {
  const link = `oatmeal://signed-in?${new URLSearchParams({ token, site })}`
  const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!)
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Signed in · ${esc(brand)}</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#FCF8EA;color:#1C1915;font:16px/1.5 Figtree,system-ui,sans-serif}
main{text-align:center;padding:24px}h1{font:400 34px/1.1 "Young Serif",Georgia,serif;margin:0 0 10px}p{color:#6E665A;margin:0 0 22px}
a{display:inline-block;background:#F6D27C;color:#1C1915;border:1.5px solid #1C1915;border-radius:10px;padding:12px 20px;font-weight:600;text-decoration:none;box-shadow:3px 3px 0 #1C1915}</style>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Figtree:wght@400;600&family=Young+Serif&display=swap"></head>
<body><main><h1>You're signed in.</h1><p>Head back to ${esc(brand)} on your Mac.</p><a href="${esc(link)}">Open ${esc(brand)}</a></main>
<script>location.href=${JSON.stringify(link)}</script></body></html>`
  const headers = new Headers({ 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' })
  for (const c of cookies) headers.append('Set-Cookie', c)
  return new Response(html, { headers })
}
