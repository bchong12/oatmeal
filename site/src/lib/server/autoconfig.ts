// What the site sets up on Whop by itself, so the owner never runs a command for it: the address
// "Sign in with Whop" sends people back to. It runs once per server instance (from /setup and
// sign-in) and only changes what is missing.

import { env } from '../env'
import { whopApi } from '../whop'

const RETRY_MS = 60_000

interface App {
  base_url?: string | null
  redirect_uris?: string[] | null
}

export interface AutoSetup {
  signIn: boolean
  problem: string
}

let learnedUrl = ''
let running: { at: number; done: boolean; result: Promise<AutoSetup> } | null = null

/** The site's public address: APP_URL if set, else the one Whop gave the app, else the fallback. */
export function siteUrl(fallback = ''): string {
  return env.appUrl || learnedUrl || fallback.replace(/\/$/, '')
}

/** Registers the sign-in callback if it's missing. Safe to call often: it does the work once per instance. */
export function ensureWhopSetup(): Promise<AutoSetup> {
  if (!env.whopAppId) return Promise.resolve({ signIn: false, problem: 'Not running on Whop hosting.' })
  if (running && (running.done || Date.now() - running.at < RETRY_MS)) return running.result
  const attempt = { at: Date.now(), done: false, result: setUp() }
  running = attempt
  attempt.result.then((r) => (attempt.done = !r.problem))
  return attempt.result
}

async function setUp(): Promise<AutoSetup> {
  const appId = env.whopAppId
  try {
    const app = await whopApi<App>(`apps/${appId}`)
    learnedUrl = (app.base_url ?? '').replace(/\/$/, '')
    const base = siteUrl()
    if (!base) throw new Error('Whop gave no address for this app.')
    const callback = `${base}/api/auth/whop/callback`
    const redirects = app.redirect_uris ?? []
    if (!redirects.includes(callback)) {
      await whopApi(`apps/${appId}`, { method: 'PATCH', body: { redirect_uris: [...redirects, callback] } })
      console.log('[setup] registered the sign-in callback on Whop')
    }
    return { signIn: true, problem: '' }
  } catch (error) {
    const problem = `Couldn't update the app on Whop: ${error instanceof Error ? error.message : String(error)}`
    console.error('[setup]', problem)
    return { signIn: false, problem }
  }
}
