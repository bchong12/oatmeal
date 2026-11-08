import { createFileRoute } from '@tanstack/react-router'
import { brandFrom } from '#/lib/brand'
import { env } from '#/lib/env'
import { json } from '#/lib/server/account'
import { baseUrl } from '#/lib/server/http'

// What the Mac app shows once it's connected to this site (`oatmeal://connect?site=…`).
export const Route = createFileRoute('/api/app/config')({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const base = baseUrl(request, env.appUrl)
        return json({
          brand: brandFrom(env.read).name,
          signIn: Boolean(env.whopAppId && env.sessionSecret),
          oatmealAI: Boolean(env.anthropicKey),
          signInUrl: `${base}/api/auth/whop?app=1`,
          pricingUrl: `${base}/pricing`,
          accountUrl: `${base}/account`,
        })
      },
    },
  },
})
