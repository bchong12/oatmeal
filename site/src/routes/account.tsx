import { Link, createFileRoute, redirect } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { Card, PageIntro } from '#/components/site/Page'
import { Shell } from '#/components/site/Shell'
import { useBrand } from '#/lib/brand'
import { getAccount } from '#/lib/server/fns'

export const Route = createFileRoute('/account')({
  loader: async () => {
    const account = await getAccount()
    if (!account) throw redirect({ to: '/login' })
    return account
  },
  head: ({ match }) => ({ meta: [{ title: `Account · ${match.context.brand.name}` }, { name: 'robots', content: 'noindex' }] }),
  component: Account,
})

function Account() {
  const account = Route.useLoaderData()
  const brand = useBrand()
  const [connect, setConnect] = useState('')
  useEffect(() => setConnect(`oatmeal://connect?${new URLSearchParams({ site: window.location.origin })}`), [])
  const paid = account.plan === 'pro' || account.plan === 'business'

  return (
    <Shell>
      <PageIntro eyebrow="Account" title={account.name ? `Hi, ${account.name.split(' ')[0]}.` : 'Your account'}>
        {account.email && <p className="text-[16px] text-muted">{account.email}</p>}
      </PageIntro>
      <section className="mx-auto grid max-w-[880px] gap-5 px-6 md:grid-cols-2">
        <Card className="flex flex-col gap-3 p-6">
          <span className="text-[13px] font-semibold tracking-[1px] text-ink/55 uppercase">Plan</span>
          <span className="font-serif text-[34px] leading-none">{account.planName ?? 'Unknown'}</span>
          <p className="text-[15px] text-muted">
            {account.plan === null
              ? "We couldn't check your plan just now. Refresh in a minute."
              : paid
                ? 'Every meeting, forever, and Oatmeal AI writes your notes.'
                : 'Your last 30 days of meetings, with notes by your own AI.'}
          </p>
          {paid ? (
            <a href="https://whop.com/@me/settings/memberships/" className="btn-outline mt-2 py-2.5 text-[14px]">
              Manage billing
            </a>
          ) : (
            <Link to="/pricing" className="btn-ink mt-2 py-2.5 text-[14px]">
              Upgrade to Pro
            </Link>
          )}
        </Card>
        <Card className="flex flex-col gap-3 p-6">
          <span className="text-[13px] font-semibold tracking-[1px] text-ink/55 uppercase">The Mac app</span>
          <span className="font-serif text-[26px] leading-tight">Use your plan in {brand.name}</span>
          <p className="text-[15px] text-muted">Open the app on this Mac, then sign in from Settings › Account.</p>
          <div className="mt-2 flex flex-col gap-3 sm:flex-row">
            <a href={connect || undefined} className="btn-honey flex-1 py-2.5 text-[14px]">
              Connect the app
            </a>
            <Link to="/download" className="btn-outline flex-1 py-2.5 text-[14px]">
              Download
            </Link>
          </div>
        </Card>
      </section>
      <p className="mt-10 text-center">
        <a href="/api/auth/logout" className="text-[14px] font-semibold text-ink/60 underline underline-offset-4">
          Sign out
        </a>
      </p>
    </Shell>
  )
}
