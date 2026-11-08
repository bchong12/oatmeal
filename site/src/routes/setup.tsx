import { createFileRoute } from '@tanstack/react-router'
import { Check, X } from 'lucide-react'
import { useState } from 'react'
import { Card, PageIntro } from '#/components/site/Page'
import { Shell } from '#/components/site/Shell'
import { getSetupStatus } from '#/lib/server/fns'

// The owner's checklist after deploying the blueprint: each step turns green once it's done.
export const Route = createFileRoute('/setup')({
  loader: () => getSetupStatus(),
  head: ({ match }) => ({ meta: [{ title: `Set up · ${match.context.brand.name}` }, { name: 'robots', content: 'noindex' }] }),
  component: Setup,
})

function CopyLine({ value }: { value: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <div className="flex items-center gap-1 rounded-[10px] border border-line bg-cream p-1 pl-3">
      <input readOnly aria-label="Copy this" value={value} onFocus={(e) => e.target.select()} className="min-w-0 flex-1 bg-transparent py-1.5 font-mono text-[12px] outline-none" />
      <button
        type="button"
        className="shrink-0 rounded-[8px] border border-ink/20 px-3 py-1.5 text-[12px] font-semibold hover:bg-wash"
        onClick={async () => {
          await navigator.clipboard.writeText(value).catch(() => {})
          setCopied(true)
        }}
      >
        {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  )
}

function Step({ n, title, done, optional, children }: { n: number; title: string; done: boolean; optional?: boolean; children: React.ReactNode }) {
  return (
    <li className="grid gap-4 border-t border-line py-7 md:grid-cols-[260px_minmax(0,1fr)] md:gap-10">
      <div className="flex items-start justify-between gap-3 md:flex-col md:justify-start">
        <div>
          <span className="text-[12px] font-semibold text-ink/50">0{n}</span>
          <h2 className={`font-serif text-[24px] leading-tight ${done ? 'text-ink/50' : ''}`}>{title}</h2>
        </div>
        {done ? (
          <span className="flex items-center gap-1.5 text-[13px] font-bold text-good">
            <Check size={15} aria-hidden /> Done
          </span>
        ) : (
          <span className="text-[13px] font-semibold text-ink/50">{optional ? 'Optional' : 'To do'}</span>
        )}
      </div>
      <div className="flex flex-col gap-3 text-[15px] leading-[23px] text-muted">{done ? <p>All set.</p> : children}</div>
    </li>
  )
}

function Setup() {
  const s = Route.useLoaderData()
  const app = s.appId ? ` --app ${s.appId}` : ''
  const secret = (pair: string) => `whop apps secrets set${app} --secret ${pair}`
  const storeDone = s.plans.filter((p) => !p.comingSoon).every((p) => p.linked)
  const required = [s.sessionSecret, storeDone]
  const left = required.filter((d) => !d).length

  return (
    <Shell>
      <PageIntro eyebrow="Set up your site" title={left === 0 ? 'Your site is live.' : `${left} ${left === 1 ? 'step' : 'steps'} to go live.`}>
        <p className="max-w-[600px] text-[16px] leading-[25px] text-muted">
          Secrets are set from your computer with the Whop CLI (<code>npm i -g @whop/cli</code>, then <code>whop login</code>). Redeploy after setting
          one; a step that stays open a minute later means the new build isn't live yet.
        </p>
      </PageIntro>

      <ol className="mx-auto max-w-[1000px] border-b border-line px-6">
        <Step n={1} title="Sign-in key" done={s.sessionSecret}>
          <p>Signs people in, on this site and in the Mac app. Any long random string works; this makes one for you:</p>
          <CopyLine value={secret('SESSION_SECRET=$(openssl rand -hex 32)')} />
        </Step>

        <Step n={2} title="Products in your store" done={storeDone}>
          <p>
            Each plan sells through the product in your store whose title contains its name. Deploying the blueprint copied them; if one is missing or
            renamed, fix it in your dashboard under Products.
          </p>
          <ul className="grid gap-2 sm:grid-cols-3">
            {s.plans.map((p) => (
              <li key={p.id} className={`flex items-center gap-2 ${p.linked ? 'text-ink' : ''}`}>
                {p.linked ? <Check size={15} className="text-good" aria-label="On sale" /> : <X size={15} aria-label="Missing" />}
                {p.name}
                {p.comingSoon && <span className="text-[12px] text-ink/45">(coming soon)</span>}
              </li>
            ))}
          </ul>
        </Step>

        <Step n={3} title="The Mac download" done={s.downloadConfigured || s.download.ready} optional>
          <p>
            "Download for Mac" points at the open-source app's latest release. To ship your own signed build instead, upload it anywhere and set its link:
          </p>
          <CopyLine value={secret('DOWNLOAD_URL=https://example.com/Oatmeal.dmg')} />
        </Step>

        <Step n={4} title="Oatmeal AI" done={s.oatmealAI} optional>
          <p>
            Lets Pro members get notes written without installing Claude Code, Codex or Gemini CLI. Uses your Claude API key (console.anthropic.com),
            so you pay for those notes.
          </p>
          <CopyLine value={secret('ANTHROPIC_API_KEY=sk-ant-...')} />
        </Step>

        <li className="grid gap-4 border-t border-line py-7 md:grid-cols-[260px_minmax(0,1fr)] md:gap-10">
          <div>
            <span className="text-[12px] font-semibold text-ink/50">Done for you</span>
            <h2 className="font-serif text-[24px]">Sign-in address</h2>
          </div>
          <div className="flex flex-col gap-3 text-[15px] text-muted">
            {s.signIn ? (
              <p className="flex items-center gap-2 text-ink">
                <Check size={15} className="text-good" aria-hidden /> Registered {s.origin}/api/auth/whop/callback with Whop.
              </p>
            ) : (
              <>
                <p>{s.onWhop ? `Whop didn't let the site do this itself (${s.problem}). Run this once:` : 'This happens by itself once the site runs on Whop.'}</p>
                {s.onWhop && <CopyLine value={`whop apps update ${s.appId} --redirect_uris '["${s.origin}/api/auth/whop/callback"]'`} />}
              </>
            )}
          </div>
        </li>
      </ol>
      <div className="mx-auto max-w-[1000px] px-6 pt-8">
        <Card className="p-6 text-[15px] leading-[23px] text-muted">
          <strong className="text-ink">Your customers:</strong> they download the app, click "Connect" on your download or account page, and sign in from
          Settings › Account. The app then checks their plan with this site, so a Pro purchase in your store unlocks Pro in the app straight away.
        </Card>
      </div>
    </Shell>
  )
}
