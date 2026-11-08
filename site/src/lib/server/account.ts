// Who is signed in: from the site's cookie, or from the Mac app's bearer token.

import { env } from '../env'
import { readSession, SESSION_COOKIE, type Session } from '../session'
import { readCookie } from './http'

export async function webSession(request: Request): Promise<Session | null> {
  const session = await readSession(readCookie(request, SESSION_COOKIE), env.sessionSecret)
  return session?.kind === 'web' ? session : null
}

export async function appSession(request: Request): Promise<Session | null> {
  const header = request.headers.get('authorization') ?? ''
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : ''
  const session = await readSession(token, env.sessionSecret)
  return session?.kind === 'app' ? session : null
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
}
