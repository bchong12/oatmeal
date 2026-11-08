// The store's own products and checkout links, read from Whop. A deployed copy of the blueprint
// gets its own copies of the products, so plans are matched by title instead of hard-coded ids.

import { env } from './env'
import { whopApi } from './whop'

export interface CatalogEntry {
  productId: string
  /** Billed monthly, or a one-time price. */
  checkoutUrl: string
  /** Billed yearly, when the product has a yearly option. */
  yearlyCheckoutUrl: string
}

interface Links {
  monthly: string
  yearly: string
}

interface Product {
  id: string
  title: string
}

interface Plan {
  id: string
  purchase_url?: string | null
  visibility?: string
  /** Days between charges; null for a one-time price. */
  billing_period?: number | null
}

const CACHE_MS = 5 * 60_000
const RETRY_MS = 60_000
let cached: { at: number; ttl: number; products: Product[] } | null = null
const planCache = new Map<string, Promise<Links>>()

const whopGet = <T>(path: string) => whopApi<T>(path)

async function storeProducts(): Promise<Product[]> {
  if (!env.whopAccountId) return []
  if (cached && Date.now() - cached.at < cached.ttl) return cached.products
  try {
    const params = new URLSearchParams({ account_id: env.whopAccountId, first: '50', visibilities: 'visible' })
    const body = await whopGet<{ data: Product[] }>(`products?${params}`)
    cached = { at: Date.now(), ttl: CACHE_MS, products: body.data ?? [] }
    planCache.clear()
  } catch (error) {
    console.error('Could not read the store catalog:', error)
    cached = { at: Date.now(), ttl: RETRY_MS, products: cached?.products ?? [] }
  }
  return cached.products
}

/** The product whose title names this plan: an exact title first, then the name as a whole word. */
export function matchProduct<P extends Product>(products: P[], name: string): P | null {
  const wanted = name.trim().toLowerCase()
  const word = new RegExp(`(^|[^a-z0-9])${wanted.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}($|[^a-z0-9])`, 'i')
  return products.find((p) => p.title.trim().toLowerCase() === wanted) ?? products.find((p) => word.test(p.title)) ?? null
}

/** A product's monthly (or one-time) and yearly checkout links, from its visible pricing options. */
export function pickLinks(plans: Plan[]): Links {
  const buyable = plans.filter((p) => p.visibility !== 'hidden' && p.visibility !== 'archived' && p.purchase_url)
  const yearly = buyable.find((p) => (p.billing_period ?? 0) >= 360)
  const monthly = buyable.find((p) => p !== yearly && (p.billing_period ?? 0) < 360)
  return { monthly: monthly?.purchase_url ?? '', yearly: yearly?.purchase_url ?? '' }
}

async function checkoutUrlFor(productId: string): Promise<Links> {
  let pending = planCache.get(productId)
  if (!pending) {
    pending = whopGet<{ data: Plan[] }>(`variants?${new URLSearchParams({ product_ids: productId, first: '10' })}`)
      .then(({ data }) => pickLinks(data))
      .catch((error) => {
        console.error(`Could not read plans for ${productId}:`, error)
        planCache.delete(productId)
        return { monthly: '', yearly: '' }
      })
    planCache.set(productId, pending)
  }
  return pending
}

/** The store's product and checkout link for a plan or extra with this name, if it sells one. */
export async function catalogEntry(name: string): Promise<CatalogEntry | null> {
  const product = matchProduct(await storeProducts(), name)
  if (!product) return null
  const links = await checkoutUrlFor(product.id)
  return { productId: product.id, checkoutUrl: links.monthly, yearlyCheckoutUrl: links.yearly }
}

/** Tests: forget what was read. */
export function resetCatalog() {
  cached = null
  planCache.clear()
}
