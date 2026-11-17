// "Free to start. Pro when it sticks." A summary of the plans as Notion-style cards; prices and features
// come from oatmeal.config.ts and the full page lives at /pricing.

import { Link } from '@tanstack/react-router'
import { config, type PlanConfig } from '../../../oatmeal.config'
import { Highlight } from './Hero'

function Price({ plan }: { plan: PlanConfig }) {
  return (
    <div className="flex items-baseline gap-[6px]">
      <span className="text-[44px] font-semibold tracking-[-0.03em]">${plan.monthly}</span>
      {plan.monthly > 0 && (
        <span className="text-[15px] text-black/55">
          {plan.id === 'business' ? '/ person / mo' : '/ month'}
        </span>
      )}
    </div>
  )
}

function Action({ plan }: { plan: PlanConfig }) {
  if (plan.comingSoon) {
    return (
      <div className="flex min-h-[40px] items-center justify-center rounded-[8px] border border-dashed border-black/20">
        <span className="text-[15px] font-medium text-black/45">Coming soon</span>
      </div>
    )
  }
  if (plan.monthly === 0) {
    return (
      <Link to="/download" className="btn-outline min-h-[40px] text-[15px]">
        Get it for Mac
      </Link>
    )
  }
  return (
    <Link
      to="/pricing"
      className={`${plan.id === 'pro' ? 'btn-ink' : 'btn-outline'} min-h-[40px] text-[15px]`}
    >
      Start {plan.name}
    </Link>
  )
}

export function Pricing() {
  return (
    <section className="oat-enter mx-auto flex max-w-[1240px] flex-col items-center gap-[40px] px-5 pb-[64px] sm:gap-[48px] sm:pb-[96px]">
      <h2 className="text-center font-serif text-[clamp(36px,5.4vw,64px)] leading-[1.08] tracking-[-0.04em] [text-wrap:balance]">
        Free to start. <Highlight tone="green">Pro</Highlight> when it sticks.
      </h2>
      <div className="grid w-full gap-[24px] md:grid-cols-3">
        {config.plans.map((plan) => {
          const pro = plan.id === 'pro'
          return (
            <div
              key={plan.id}
              className={`flex flex-col gap-[18px] rounded-[12px] p-[28px] ${
                pro
                  ? 'bg-white shadow-[rgba(0,0,0,0.01)_0_0_1px,rgba(0,0,0,0.02)_0_0_2px,rgba(0,0,0,0.027)_0_2px_7px,rgba(0,0,0,0.06)_0_12px_32px] ring-1 ring-black/10'
                  : 'bg-[#F9F9F8]'
              }`}
            >
              {pro ? (
                <div className="flex items-center justify-between">
                  <span className="font-serif text-[26px] tracking-[-0.02em]">{plan.name}</span>
                  <span className="rounded-full bg-[#DBEDDB] px-[10px] py-[3px] text-[12px] font-medium text-[#2E7D55]">Most loved</span>
                </div>
              ) : (
                <span className="font-serif text-[26px] tracking-[-0.02em]">{plan.name}</span>
              )}
              <Price plan={plan} />
              <Action plan={plan} />
              <div className="flex flex-col gap-[10px]">
                {plan.features.map((f) => (
                  <span key={f} className="text-[15px] text-black/80">
                    ✓ {f}
                  </span>
                ))}
              </div>
            </div>
          )
        })}
      </div>
    </section>
  )
}
