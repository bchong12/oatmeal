// Signed tokens: the website's sign-in cookie, and the token the Mac app keeps after signing in.

const encoder = new TextEncoder()
export const SESSION_COOKIE = 'oat_session'
export const SESSION_DAYS = 30
/** The Mac app stays signed in longer; its plan is still checked with Whop every time it asks. */
export const APP_TOKEN_DAYS = 180

export interface Session {
  whopUserId: string
  name: string | null
  email: string | null
  /** "web" for the site's cookie, "app" for the Mac app's token. */
  kind: 'web' | 'app'
  exp: number
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function fromB64url(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4)
  return Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))
}

async function hmac(secret: string, data: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, [
    'sign',
  ])
  return b64url(new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(data))))
}

export async function signSession(session: Omit<Session, 'exp'>, secret: string, now = Date.now()): Promise<string> {
  if (!secret) throw new Error('SESSION_SECRET is not set')
  const days = session.kind === 'app' ? APP_TOKEN_DAYS : SESSION_DAYS
  const payload = b64url(encoder.encode(JSON.stringify({ ...session, exp: now + days * 86_400_000 })))
  return `${payload}.${await hmac(secret, payload)}`
}

export async function readSession(token: string | undefined, secret: string, now = Date.now()): Promise<Session | null> {
  if (!token || !secret) return null
  const [payload, signature] = token.split('.')
  if (!payload || !signature) return null
  if ((await hmac(secret, payload)) !== signature) return null
  try {
    const session = JSON.parse(new TextDecoder().decode(fromB64url(payload))) as Session
    return session.exp > now ? session : null
  } catch {
    return null
  }
}

/** Random string for OAuth state and PKCE verifiers. */
export function randomToken(bytes = 32): string {
  return b64url(crypto.getRandomValues(new Uint8Array(bytes)))
}

export async function pkceChallenge(verifier: string): Promise<string> {
  return b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(verifier))))
}
