// Make the business yours: name, prices, and what each plan includes.
// Checkout links are found in your own store: a product whose title contains a plan's name ("Pro",
// "Business") sells that plan, monthly and yearly. Nothing here links to a particular store, so every
// deployed copy sells through its own products.

export type PlanId = 'free' | 'pro' | 'business'

export interface PlanConfig {
  id: PlanId
  name: string
  /** Dollars per month, billed monthly. 0 is the free plan. */
  monthly: number
  /** Dollars per month, billed yearly. */
  yearly: number
  /** Days of meetings kept in the app; null for all of them. */
  historyDays: number | null
  /** Shown but not for sale yet. */
  comingSoon: boolean
  blurb: string
  features: string[]
}

export const config = {
  brand: {
    name: 'Oatmeal',
    tagline: 'Meeting notes and dictation for your Mac. Transcribed on your Mac, written by the AI you already pay for.',
    supportEmail: 'support@example.com',
    companyName: 'Oatmeal',
  },
  /** Where "Download for Mac" points. DOWNLOAD_URL wins; empty uses the open-source app's latest release. */
  downloadUrl: '',
  /** The open-source app, for the latest release and "build it yourself". */
  sourceRepo: 'bchong12/oatmeal',
  plans: [
    {
      id: 'free',
      name: 'Free',
      monthly: 0,
      yearly: 0,
      historyDays: 30,
      comingSoon: false,
      blurb: 'Everything on your Mac, with your own AI.',
      features: [
        'Unlimited recording and dictation',
        'Transcribed on your Mac',
        'Notes by Claude Code, Codex or Gemini CLI',
        '30 days of meeting history',
      ],
    },
    {
      id: 'pro',
      name: 'Pro',
      monthly: 14,
      yearly: 12,
      historyDays: null,
      comingSoon: false,
      blurb: 'For people who live in meetings.',
      features: ['Everything in Free', 'Unlimited meeting history', 'Oatmeal AI writes notes, no setup', 'Priority support'],
    },
    {
      id: 'business',
      name: 'Business',
      monthly: 35,
      yearly: 29,
      historyDays: null,
      comingSoon: true,
      blurb: 'For teams that share what was said.',
      features: ['Everything in Pro', 'Shared folders', 'Admin and billing in one place'],
    },
  ] satisfies PlanConfig[],
}
