// "Free to start. Pro when it sticks." A summary of the plans on espresso; prices and features come from
// oatmeal.config.ts and the full page lives at /pricing. Purist node Pt51qy.

import { Link } from '@tanstack/react-router'
import { config, type PlanConfig } from '../../../oatmeal.config'

function Price({ plan }: { plan: PlanConfig }) {
  return (
    <div className="flex items-baseline gap-[6px]">
      <span className="text-[48px] font-bold tracking-[-0.03em]">${plan.monthly}</span>
      {plan.monthly > 0 && (
        <span className={`text-[15px] ${plan.id === 'pro' ? 'text-ink/75' : 'text-ink/70'}`}>
          {plan.id === 'business' ? '/ person / mo' : '/ month'}
        </span>
      )}
    </div>
  )
}

function Action({ plan }: { plan: PlanConfig }) {
  if (plan.comingSoon) {
    return (
      <div className="flex justify-center rounded-[10px] border-2 border-dashed border-ink/40 p-[14px]">
        <span className="text-[15px] font-bold text-ink/55">Coming soon</span>
      </div>
    )
  }
  if (plan.monthly === 0) {
    return (
      <Link to="/download" className="flex justify-center rounded-[10px] border-2 border-ink bg-white p-[14px] text-[15px] font-bold transition-colors hover:bg-wash">
        Get it for Mac
      </Link>
    )
  }
  return (
    <Link
      to="/pricing"
      className={`flex justify-center rounded-[10px] p-[14px] text-[15px] font-bold transition-colors ${
        plan.id === 'pro' ? 'bg-ink text-honey hover:bg-[#3a342c]' : 'border-2 border-ink bg-white hover:bg-wash'
      }`}
    >
      Start {plan.name}
    </Link>
  )
}

export function Pricing() {
  return (
    <section className="oat-enter flex flex-col items-center gap-10 bg-espresso px-5 py-20 sm:gap-[48px] min-[1200px]:py-[120px]">
      <h2 className="flex flex-col items-center text-center font-serif font-normal tracking-[-0.035em] text-cream text-[clamp(38px,6vw,72px)] leading-[1.08]">
        <span>Free to start.</span>
        <span className="text-honey">Pro when it sticks.</span>
      </h2>
      <div className="grid w-full max-w-[1100px] gap-[24px] md:grid-cols-3">
        {config.plans.map((plan) => {
          const pro = plan.id === 'pro'
          return (
            <div
              key={plan.id}
              className={`flex flex-col gap-[18px] rounded-[20px] border-[1.5px] p-[30px] ${
                pro ? 'border-ink bg-honey shadow-[4px_4px_0_var(--cream)]' : 'border-ink/90 bg-cream'
              }`}
            >
              {pro ? (
                <div className="flex items-center justify-between">
                  <span className="font-serif text-[30px]">{plan.name}</span>
                  <span className="rounded-full bg-ink px-[10px] py-[4px] text-[12px] font-bold text-honey">Most loved</span>
                </div>
              ) : (
                <span className="font-serif text-[30px]">{plan.name}</span>
              )}
              <Price plan={plan} />
              <Action plan={plan} />
              <div className="flex flex-col gap-[10px]">
                {plan.features.map((f) => (
                  <span key={f} className="text-[15px]">
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
