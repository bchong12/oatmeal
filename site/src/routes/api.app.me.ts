import { createFileRoute } from '@tanstack/react-router'
import { env } from '#/lib/env'
import { planConfig, planFor } from '#/lib/plans'
import { appSession, json } from '#/lib/server/account'

// The Mac app asks who it's signed in as and what that unlocks. The plan is checked with Whop.
export const Route = createFileRoute('/api/app/me')({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const session = await appSession(request)
        if (!session) return json({ error: 'Sign in again.' }, 401)
        const plan = await planFor(session.whopUserId).catch((error) => {
          console.error('[me] plan check failed:', error)
          return null
        })
        if (!plan) return json({ error: 'Could not check your plan. Try again in a minute.' }, 502)
        const config = planConfig(plan)
        return json({
          name: session.name,
          email: session.email,
          plan,
          planName: config.name,
          historyDays: config.historyDays,
          oatmealAI: plan !== 'free' && Boolean(env.anthropicKey),
        })
      },
    },
  },
})
