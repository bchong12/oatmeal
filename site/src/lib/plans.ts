// Plans: what oatmeal.config.ts says they include, where to buy them, and which one someone has.
// A checkout link comes from a PLAN_<ID>_URL / PLAN_<ID>_YEARLY_URL / PLAN_<ID>_PRODUCT_ID secret if
// one is set, then from the store's own matching product (see catalog.ts).

import { config, type PlanConfig, type PlanId } from '../../oatmeal.config'
import { catalogEntry } from './catalog'
import { env } from './env'
import { hasAccess } from './whop'

export interface ResolvedPlan extends PlanConfig {
  checkoutUrl: string
  yearlyCheckoutUrl: string
  /** The store product whose membership unlocks this plan; empty when the store doesn't sell it. */
  productId: string
}

export function planConfig(id: PlanId): PlanConfig {
  return config.plans.find((p) => p.id === id) ?? config.plans[0]
}

export async function resolvedPlans(): Promise<ResolvedPlan[]> {
  return Promise.all(
    config.plans.map(async (plan) => {
      const found = await catalogEntry(plan.name).catch(() => null)
      return {
        ...plan,
        checkoutUrl: env.plan(plan.id, 'URL') || found?.checkoutUrl || '',
        yearlyCheckoutUrl: env.plan(plan.id, 'YEARLY_URL') || found?.yearlyCheckoutUrl || '',
        productId: env.plan(plan.id, 'PRODUCT_ID') || found?.productId || '',
      }
    }),
  )
}

const CACHE_MS = 2 * 60_000
const planCache = new Map<string, { at: number; plan: PlanId }>()

/** The best paid plan this Whop user has a membership for, else Free. Checked with Whop, cached briefly. */
export async function planFor(whopUserId: string): Promise<PlanId> {
  const hit = planCache.get(whopUserId)
  if (hit && Date.now() - hit.at < CACHE_MS) return hit.plan
  const plans = await resolvedPlans()
  let plan: PlanId = 'free'
  for (const id of ['business', 'pro'] as const) {
    const productId = plans.find((p) => p.id === id)?.productId
    if (productId && (await hasAccess(whopUserId, productId))) {
      plan = id
      break
    }
  }
  planCache.set(whopUserId, { at: Date.now(), plan })
  return plan
}

/** Tests: forget cached plans. */
export function resetPlanCache() {
  planCache.clear()
}
