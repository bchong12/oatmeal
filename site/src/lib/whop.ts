// Whop: "Sign in with Whop", and whether someone has bought a plan.
//
// On Whop hosting, server-side calls to api.whop.com get the operator's API key attached
// automatically. Sign-in calls send `x-whop-inject-key: none` so no key goes with them.

import { env } from './env'

export const API_VERSION = '2026-10-28'

/** A call to Whop's API as the operator: the hosting proxy attaches the key, `whop apps dev` passes one. */
export async function whopApi<T>(path: string, init: { method?: string; body?: unknown } = {}): Promise<T> {
  const headers: Record<string, string> = { 'Api-Version-Date': API_VERSION }
  if (env.whopApiKey) headers.Authorization = `Bearer ${env.whopApiKey}`
  if (init.body !== undefined) headers['Content-Type'] = 'application/json'
  const res = await fetch(`${env.whopApiOrigin}/api/v1/${path}`, {
    method: init.method ?? 'GET',
    headers,
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  })
  if (!res.ok) throw new Error(`Whop ${init.method ?? 'GET'} ${path.split('?')[0]} failed (${res.status}): ${(await res.text()).slice(0, 300)}`)
  return (await res.json()) as T
}

/** True when this Whop user has access to the product (an active membership). */
export async function hasAccess(whopUserId: string, productId: string): Promise<boolean> {
  const res = await whopApi<{ has_access?: boolean }>(`users/${encodeURIComponent(whopUserId)}/access/${encodeURIComponent(productId)}`)
  return res.has_access === true
}

// ---- Sign in with Whop (OAuth 2 with PKCE) ----

export function whopAuthorizeUrl(opts: { clientId: string; redirectUri: string; state: string; codeChallenge: string }): string {
  const params = new URLSearchParams({
    response_type: 'code',
    client_id: opts.clientId,
    redirect_uri: opts.redirectUri,
    scope: 'openid profile email',
    state: opts.state,
    nonce: opts.state,
    code_challenge: opts.codeChallenge,
    code_challenge_method: 'S256',
  })
  return `${env.whopApiOrigin}/oauth/authorize?${params}`
}

export interface WhopUser {
  id: string
  name: string | null
  email: string | null
}

export async function whopExchangeCode(opts: {
  clientId: string
  clientSecret: string
  redirectUri: string
  code: string
  codeVerifier: string
}): Promise<WhopUser> {
  const tokenRes = await fetch(`${env.whopApiOrigin}/oauth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-whop-inject-key': 'none' },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      code: opts.code,
      redirect_uri: opts.redirectUri,
      client_id: opts.clientId,
      code_verifier: opts.codeVerifier,
      ...(opts.clientSecret ? { client_secret: opts.clientSecret } : {}),
    }),
  })
  if (!tokenRes.ok) throw new Error(`Whop sign-in failed (${tokenRes.status}): ${await tokenRes.text()}`)
  const tokens = (await tokenRes.json()) as { access_token: string }
  const infoRes = await fetch(`${env.whopApiOrigin}/oauth/userinfo`, {
    headers: { Authorization: `Bearer ${tokens.access_token}`, 'x-whop-inject-key': 'none' },
  })
  if (!infoRes.ok) throw new Error(`Whop user lookup failed (${infoRes.status})`)
  const info = (await infoRes.json()) as { sub: string; name?: string; email?: string }
  return { id: info.sub, name: info.name ?? null, email: info.email ?? null }
}
