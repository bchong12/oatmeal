import { describe, expect, it } from 'vitest'
import { APP_TOKEN_DAYS, SESSION_DAYS, readSession, signSession } from './session'

const who = { whopUserId: 'user_1', name: 'Maya', email: 'maya@example.com' }

describe('signed sessions', () => {
  it('round-trips and keeps the kind', async () => {
    const token = await signSession({ ...who, kind: 'app' }, 'secret')
    const session = await readSession(token, 'secret')
    expect(session).toMatchObject({ ...who, kind: 'app' })
  })

  it('rejects a token signed with another secret, or edited', async () => {
    const token = await signSession({ ...who, kind: 'web' }, 'secret')
    expect(await readSession(token, 'other')).toBeNull()
    const [payload, sig] = token.split('.')
    expect(await readSession(`${payload}x.${sig}`, 'secret')).toBeNull()
  })

  it('app tokens last longer than the website cookie, and both expire', async () => {
    const now = Date.now()
    const web = await signSession({ ...who, kind: 'web' }, 'secret', now)
    const app = await signSession({ ...who, kind: 'app' }, 'secret', now)
    const day = 86_400_000
    expect(await readSession(web, 'secret', now + (SESSION_DAYS + 1) * day)).toBeNull()
    expect(await readSession(app, 'secret', now + (SESSION_DAYS + 1) * day)).not.toBeNull()
    expect(await readSession(app, 'secret', now + (APP_TOKEN_DAYS + 1) * day)).toBeNull()
  })

  it('refuses to sign without a secret', async () => {
    await expect(signSession({ ...who, kind: 'web' }, '')).rejects.toThrow()
  })
})
