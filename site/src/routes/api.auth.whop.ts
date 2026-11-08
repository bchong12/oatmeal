import { createFileRoute } from '@tanstack/react-router'
import { env } from '#/lib/env'
import { ensureWhopSetup } from '#/lib/server/autoconfig'
import { baseUrl, cookie, redirect } from '#/lib/server/http'
import { pkceChallenge, randomToken } from '#/lib/session'
import { whopAuthorizeUrl } from '#/lib/whop'

// "Sign in with Whop", for the website and for the Mac app (`?app=1`, opened by Settings › Account).
export const Route = createFileRoute('/api/auth/whop')({
  server: {
    handlers: {
      GET: async ({ request }) => {
        if (!env.whopAppId) return new Response('Sign-in works once the site runs on Whop (APP_ID is not set).', { status: 503 })
        if (!env.sessionSecret) return redirect('/login?error=not-ready')
        // Whop only sends people back to a registered callback; the first sign-in registers it.
        await ensureWhopSetup()
        const app = new URL(request.url).searchParams.get('app') === '1'
        const state = randomToken()
        const verifier = randomToken(48)
        const url = whopAuthorizeUrl({
          clientId: env.whopAppId,
          redirectUri: `${baseUrl(request, env.appUrl)}/api/auth/whop/callback`,
          state,
          codeChallenge: await pkceChallenge(verifier),
        })
        return redirect(url, [cookie('oat_oauth', `${state}.${verifier}.${app ? 'app' : 'web'}`, 600)])
      },
    },
  },
})
