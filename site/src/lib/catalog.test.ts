import { describe, expect, it } from 'vitest'
import { matchProduct } from './catalog'

const products = [
  { id: 'prod_business', title: 'Oatmeal Business' },
  { id: 'prod_pro', title: 'Oatmeal Pro' },
  { id: 'prod_productivity', title: 'Productivity course' },
  { id: 'prod_starter', title: 'Starter' },
]

describe('matchProduct', () => {
  it('prefers an exact title', () => {
    expect(matchProduct(products, 'Starter')?.id).toBe('prod_starter')
  })
  it('matches the plan name as a whole word, ignoring case', () => {
    expect(matchProduct(products, 'pro')?.id).toBe('prod_pro')
    expect(matchProduct(products, 'Business')?.id).toBe('prod_business')
  })
  it('finds nothing when no title names the plan', () => {
    expect(matchProduct(products, 'Done-for-you setup')).toBeNull()
  })
})
