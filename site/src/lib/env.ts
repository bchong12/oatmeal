// Server-side settings. On Whop hosting these are app secrets (`whop apps secrets set`);
// locally they come from .dev.vars.

function read(name: string): string {
  return (typeof process !== 'undefined' ? process.env[name] : undefined)?.trim() ?? ''
}

export const env = {
  read,
  get appUrl() {
    return read('APP_URL').replace(/\/$/, '')
  },
  /** Signs sign-in cookies and the Mac app's tokens. Sign-in stays off until it's set. */
  get sessionSecret() {
    return read('SESSION_SECRET')
  },
  /** Turns on Oatmeal AI: Pro members without their own AI get notes written with this Claude key. */
  get anthropicKey() {
    return read('ANTHROPIC_API_KEY')
  },
  get downloadUrl() {
    return read('DOWNLOAD_URL')
  },
  /** Whop sets APP_ID on hosted apps; it doubles as the OAuth client id for "Sign in with Whop". */
  get whopAppId() {
    return read('APP_ID') || read('WHOP_APP_ID')
  },
  /** Whop hosting sets this to the business that owns the app; its products are the plans for sale. */
  get whopAccountId() {
    return read('WHOP_ACCOUNT_ID')
  },
  /** Set by `whop apps dev`; on Whop hosting the API proxy attaches the key instead. */
  get whopApiKey() {
    return read('WHOP_API_KEY')
  },
  get whopClientSecret() {
    return read('WHOP_CLIENT_SECRET')
  },
  /** Whop hosting sets this to the API origin its key-injecting proxy answers on. */
  get whopApiOrigin() {
    return (read('WHOP_API_ORIGIN') || 'https://api.whop.com').replace(/\/$/, '')
  },
  /** Plan links and product ids can be pinned with secrets; they win over the store lookup. */
  plan(id: string, field: 'URL' | 'YEARLY_URL' | 'PRODUCT_ID') {
    return read(`PLAN_${id.toUpperCase()}_${field}`)
  },
}
