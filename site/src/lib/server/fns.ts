// Server functions the pages load from.

import { createServerFn } from '@tanstack/react-start'
import { getRequest } from '@tanstack/react-start/server'
import { config } from '../../../oatmeal.config'
import { brandFrom } from '../brand'
import { env } from '../env'
import { planConfig, planFor, resolvedPlans } from '../plans'
import { webSession } from './account'
import { ensureWhopSetup, siteUrl } from './autoconfig'
import { baseUrl } from './http'

export const getBrand = createServerFn({ method: 'GET' }).handler(async () => brandFrom(env.read))

export const getPlans = createServerFn({ method: 'GET' }).handler(async () => resolvedPlans())

/** The Mac app's download: DOWNLOAD_URL, else the open-source app's latest release on GitHub. */
export const getDownload = createServerFn({ method: 'GET' }).handler(async () => download())

let release: { at: number; value: Download } | null = null

interface Download {
  url: string
  version: string | null
  /** False when there is no build to download yet, only the source. */
  ready: boolean
}

async function download(): Promise<Download> {
  const configured = env.downloadUrl || config.downloadUrl
  if (configured) return { url: configured, version: null, ready: true }
  if (release && Date.now() - release.at < 10 * 60_000) return release.value
  const repo = config.sourceRepo
  let value: Download = { url: `https://github.com/${repo}`, version: null, ready: false }
  try {
    const res = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, { headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'oatmeal-site' } })
    if (res.ok) {
      const body = (await res.json()) as { tag_name?: string; html_url?: string; assets?: { name: string; browser_download_url: string }[] }
      const dmg = body.assets?.find((a) => a.name.toLowerCase().endsWith('.dmg') || a.name.toLowerCase().endsWith('.zip'))
      if (dmg) value = { url: dmg.browser_download_url, version: body.tag_name ?? null, ready: true }
    }
  } catch (error) {
    console.error('[download] GitHub lookup failed:', error)
  }
  release = { at: Date.now(), value }
  return value
}

/** Who's signed in on the website, and their plan. Null when signed out. */
export const getAccount = createServerFn({ method: 'GET' }).handler(async () => {
  const request = getRequest()
  const session = await webSession(request)
  if (!session) return null
  const plan = await planFor(session.whopUserId).catch(() => null)
  return {
    name: session.name,
    email: session.email,
    plan,
    planName: plan ? planConfig(plan).name : null,
    site: baseUrl(request, env.appUrl),
  }
})

/** The owner's checklist after deploying: what's set, what's missing. */
export const getSetupStatus = createServerFn({ method: 'GET' }).handler(async () => {
  const request = getRequest()
  const [auto, plans, dl] = await Promise.all([ensureWhopSetup(), resolvedPlans().catch(() => []), download()])
  return {
    appId: env.whopAppId,
    onWhop: Boolean(env.whopAppId),
    origin: siteUrl(baseUrl(request, '')),
    sessionSecret: Boolean(env.sessionSecret),
    oatmealAI: Boolean(env.anthropicKey),
    downloadConfigured: Boolean(env.downloadUrl || config.downloadUrl),
    download: dl,
    plans: plans.map((p) => ({ id: p.id, name: p.name, comingSoon: p.comingSoon, linked: p.id === 'free' || Boolean(p.checkoutUrl) })),
    signIn: auto.signIn,
    problem: auto.problem,
  }
})
