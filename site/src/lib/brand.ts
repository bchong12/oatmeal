// The brand a visitor sees. BRAND_* secrets win over oatmeal.config.ts, so a deployed copy can be
// renamed without touching code.

import { useRouteContext } from '@tanstack/react-router'
import { config } from '../../oatmeal.config'

export interface Brand {
  name: string
  tagline: string
  companyName: string
  supportEmail: string
}

export function brandFrom(read: (name: string) => string): Brand {
  const name = read('BRAND_NAME') || config.brand.name
  return {
    name,
    tagline: read('BRAND_TAGLINE') || config.brand.tagline,
    companyName: read('BRAND_COMPANY') || (read('BRAND_NAME') ? name : config.brand.companyName),
    supportEmail: read('BRAND_SUPPORT_EMAIL') || config.brand.supportEmail,
  }
}

export function useBrand(): Brand {
  return useRouteContext({ from: '__root__', select: (context) => context.brand })
}
