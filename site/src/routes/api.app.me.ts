import { createFileRoute } from '@tanstack/react-router'
import { appSession, json } from '#/lib/server/account'

// The Mac app asks who it's signed in as. Oatmeal is free, so there's no plan to check.
export const Route = createFileRoute('/api/app/me')({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const session = await appSession(request)
        if (!session) return json({ error: 'Sign in again.' }, 401)
        return json({ name: session.name, email: session.email })
      },
    },
  },
})
