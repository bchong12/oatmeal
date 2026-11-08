import { Link, createFileRoute } from '@tanstack/react-router'
import { Check } from 'lucide-react'
import { useState } from 'react'
import { Card, PageIntro } from '#/components/site/Page'
import { Shell } from '#/components/site/Shell'
import type { ResolvedPlan } from '#/lib/plans'
import { getPlans } from '#/lib/server/fns'

export const Route = createFileRoute('/pricing')({
  loader: () => getPlans(),
  head: ({ match }) => ({ meta: [{ title: `Pricing · ${match.context.brand.name}` }] }),
  component: Pricing,
})

const FAQ: [string, string][] = [
  [
    'Is the free plan really free?',
    "Yes. Recording, transcription and dictation run on your Mac, and notes are written by Claude Code, Codex or Gemini CLI on the plan you already pay for. Free keeps your last 30 days of meetings.",
  ],
  ['What does Pro add?', 'Every meeting, forever, and Oatmeal AI: notes written for you without installing anything, for when you don’t have Claude Code, Codex or Gemini CLI.'],
  ['Does a bot join my calls?', 'No. Oatmeal records your mic and the call’s audio on your Mac. Nobody on the call sees anything.'],
  ['Where do my recordings go?', 'They stay on your Mac. With Oatmeal AI, the transcript of a meeting is sent to write its notes, and nothing is kept after.'],
  ['Can I cancel any time?', 'Yes, from your account. You keep Pro until the end of the period you paid for.'],
]

function Pricing() {
  const plans = Route.useLoaderData()
  const [yearly, setYearly] = useState(false)
  const anyYearly = plans.some((p) => p.yearlyCheckoutUrl)

  return (
    <Shell>
      <PageIntro eyebrow="Pricing" title="Free to start." highlight="Pro when it sticks.">
        <p className="max-w-[520px] text-[18px] leading-[27px] text-muted">
          Everything runs on your Mac for free. Pro keeps every meeting and writes notes for you.
        </p>
        {anyYearly && (
          <div className="mt-2 flex rounded-full bg-wash p-[3px] text-[14px] font-semibold" role="group" aria-label="Billing period">
            {(['Monthly', 'Yearly'] as const).map((label) => {
              const on = (label === 'Yearly') === yearly
              return (
                <button
                  key={label}
                  type="button"
                  onClick={() => setYearly(label === 'Yearly')}
                  className={`rounded-full px-4 py-[7px] transition-colors ${on ? 'bg-white shadow-[0_1px_2px_rgba(28,25,21,0.12)]' : 'text-ink/60'}`}
                  aria-pressed={on}
                >
                  {label}
                  {label === 'Yearly' && <span className="ml-1.5 text-[12px] text-honey-deep">save ~15%</span>}
                </button>
              )
            })}
          </div>
        )}
      </PageIntro>

      <section className="mx-auto grid max-w-[1080px] gap-6 px-6 md:grid-cols-3">
        {plans.map((plan) => (
          <PlanCard key={plan.id} plan={plan} yearly={yearly} />
        ))}
      </section>

      <section className="mx-auto max-w-[760px] px-6 pt-24">
        <h2 className="mb-6 font-serif text-[34px] tracking-[-0.02em]">Questions</h2>
        <div className="divide-y divide-line border-y border-line">
          {FAQ.map(([q, a]) => (
            <details key={q} className="group py-5">
              <summary className="flex cursor-pointer list-none items-center justify-between gap-4 text-[17px] font-semibold">
                {q}
                <span className="text-[22px] text-ink/40 transition-transform group-open:rotate-45">+</span>
              </summary>
              <p className="pt-3 text-[16px] leading-[25px] text-muted">{a}</p>
            </details>
          ))}
        </div>
      </section>
    </Shell>
  )
}

function PlanCard({ plan, yearly }: { plan: ResolvedPlan; yearly: boolean }) {
  const pro = plan.id === 'pro'
  const price = yearly && plan.yearly ? plan.yearly : plan.monthly
  const checkout = yearly && plan.yearlyCheckoutUrl ? plan.yearlyCheckoutUrl : plan.checkoutUrl
  const per = plan.id === 'business' ? '/ person / mo' : '/ month'

  return (
    <Card honey={pro} className="flex flex-col gap-5 p-7">
      <div className="flex items-center justify-between">
        <h3 className="font-serif text-[26px]">{plan.name}</h3>
        {pro && <span className="rounded-full bg-ink px-2.5 py-1 text-[11px] font-bold text-white">Most loved</span>}
      </div>
      <div className="flex items-baseline gap-1.5">
        <span className="font-serif text-[44px] leading-none tracking-[-0.02em]">${price}</span>
        {price > 0 && <span className="text-[14px] text-ink/60">{per}{yearly && plan.yearly ? ', billed yearly' : ''}</span>}
      </div>
      <p className="text-[15px] text-ink/75">{plan.blurb}</p>
      {plan.id === 'free' ? (
        <Link to="/download" className="btn-outline py-3 text-[15px]">
          Get it for Mac
        </Link>
      ) : plan.comingSoon || !checkout ? (
        <span className="inline-flex items-center justify-center rounded-[10px] border-[1.5px] border-dashed border-ink/30 py-3 text-[15px] font-semibold text-ink/50">
          Coming soon
        </span>
      ) : (
        <a href={checkout} className="btn-ink py-3 text-[15px]">
          Start {plan.name}
        </a>
      )}
      <ul className="flex flex-col gap-2.5 text-[15px]">
        {plan.features.map((f) => (
          <li key={f} className="flex gap-2.5">
            <Check size={17} className="mt-[3px] shrink-0" aria-hidden />
            {f}
          </li>
        ))}
      </ul>
    </Card>
  )
}
