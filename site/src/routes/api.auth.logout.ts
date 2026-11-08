import { createFileRoute } from '@tanstack/react-router'
import { cookie, redirect } from '#/lib/server/http'
import { SESSION_COOKIE } from '#/lib/session'

export const Route = createFileRoute('/api/auth/logout')({
  server: {
    handlers: {
      GET: async () => redirect('/', [cookie(SESSION_COOKIE, '', 0)]),
    },
  },
})
