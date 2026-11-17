// The Oatmeal window as a product shot: the sidebar, and a meeting that has already written itself up.
// Drawn in HTML (not a screenshot) so it stays sharp and never shows anyone's real meetings.
// From the Purist frame "Capture · 4 In the app".

import { Face, Mark } from '#/components/site/Mark'

const NAV = [
  { label: 'Recent', icon: 'M12 7v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z' },
  { label: 'Meetings', icon: 'M4 5h16v14H4zM8 9h8M8 13h5', on: true },
  { label: 'Flow', icon: 'M5 10v4M9 7v10M13 9v6M17 6v12M21 10v4' },
  { label: 'Captures', icon: 'M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3' },
]

function Icon({ d }: { d: string }) {
  return (
    <svg viewBox="0 0 24 24" className="h-[15px] w-[15px] shrink-0" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={d} />
    </svg>
  )
}

function Check({ done, children }: { done?: boolean; children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-[9px]">
      <span className={`mt-[3px] flex h-[15px] w-[15px] shrink-0 items-center justify-center rounded-[4px] border ${done ? 'border-ink bg-ink text-white' : 'border-[#D3D1CB]'}`}>
        {done && (
          <svg viewBox="0 0 12 12" className="h-[9px] w-[9px]" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden>
            <path d="m2.5 6.2 2.2 2.2 4.8-5" />
          </svg>
        )}
      </span>
      <span className={done ? 'text-ink/45 line-through' : ''}>{children}</span>
    </div>
  )
}

export function AppShot({ className = '' }: { className?: string }) {
  return (
    <div
      className={`flex overflow-hidden rounded-[10px] border border-black/10 bg-white text-left text-[14px] leading-[22px] text-ink shadow-[rgba(0,0,0,0.008)_0_0_3px,rgba(0,0,0,0.016)_0_2px_7px,rgba(0,0,0,0.02)_0_7px_14px,rgba(0,0,0,0.024)_0_13px_28px,rgba(0,0,0,0.03)_0_23px_52px,rgba(0,0,0,0.04)_0_36px_89px] ${className}`}
    >
      <aside className="hidden w-[210px] shrink-0 flex-col gap-[2px] border-r border-black/[0.06] bg-[#F7F7F5] px-[8px] py-[14px] text-black/65 md:flex">
        <div className="flex gap-[6px] px-[10px] pb-[14px]">
          <span className="h-[11px] w-[11px] rounded-full bg-[#FF5F57]" />
          <span className="h-[11px] w-[11px] rounded-full bg-[#FEBC2E]" />
          <span className="h-[11px] w-[11px] rounded-full bg-[#28C840]" />
        </div>
        <div className="flex items-center gap-[8px] px-[10px] pb-[12px]">
          <Mark size={22} />
          <span className="font-semibold text-ink">Oatmeal</span>
        </div>
        <div className="mx-[2px] mb-[10px] flex items-center justify-center gap-[7px] rounded-[7px] bg-ink py-[7px] text-[13px] font-medium text-white">
          <span className="h-[7px] w-[7px] rounded-full bg-live" />
          Record a meeting
        </div>
        {NAV.map((n) => (
          <div key={n.label} className={`flex items-center gap-[9px] rounded-[6px] px-[10px] py-[5px] ${n.on ? 'bg-black/5 font-medium text-ink' : ''}`}>
            <Icon d={n.icon} />
            {n.label}
          </div>
        ))}
        <div className="px-[10px] pt-[16px] pb-[6px] text-[12px] font-medium text-black/45">Folders</div>
        {['Clients', 'Hiring', 'Team'].map((f) => (
          <div key={f} className="flex items-center gap-[9px] rounded-[6px] px-[10px] py-[5px]">
            <Icon d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z" />
            {f}
          </div>
        ))}
      </aside>

      <div className="flex min-w-0 flex-1 flex-col gap-[18px] px-[22px] py-[26px] sm:px-[48px] sm:py-[40px]">
        <div className="flex flex-col gap-[6px]">
          <span className="text-[13px] text-black/45">Clients · Today, 10:00 am · 32 min</span>
          <h3 className="text-[26px] leading-[32px] font-bold tracking-[-0.6px] sm:text-[32px] sm:leading-[38px]">Pricing review with Maya</h3>
          <div className="flex flex-wrap items-center gap-[6px] pt-[4px] text-[13px]">
            <span className="flex items-center gap-[6px] rounded-full bg-[#F1F1EF] py-[2px] pr-[10px] pl-[3px]">
              <span className="flex h-[20px] w-[20px] items-end justify-center overflow-hidden rounded-full bg-[#DBEDDB]">
                <Face who="h" className="h-[24px] w-[24px]" />
              </span>
              Maya
            </span>
            <span className="flex items-center gap-[6px] rounded-full bg-[#F1F1EF] py-[2px] pr-[10px] pl-[3px]">
              <span className="flex h-[20px] w-[20px] items-end justify-center overflow-hidden rounded-full bg-[#FCEBC2]">
                <Face className="h-[24px] w-[24px]" />
              </span>
              You
            </span>
            <span className="rounded-full bg-[#DDEBF1] px-[10px] py-[2px] text-[#1F6C9F]">Written by Claude Code</span>
          </div>
        </div>

        <div className="flex flex-col gap-[6px]">
          <span className="font-semibold">Summary</span>
          <ul className="flex list-disc flex-col gap-[4px] pl-[20px] text-black/80">
            <li>Pro moves to $14 a month; yearly stays at $144.</li>
            <li>Existing customers keep their price until March.</li>
            <li>Maya wants the email to go out before the Friday sync.</li>
          </ul>
        </div>

        <div className="flex flex-col gap-[8px]">
          <span className="font-semibold">Next steps</span>
          <Check>
            Maya: confirm the pricing email went out, <span className="rounded-[4px] bg-[#FCEBC2] px-[4px]">Friday</span>
          </Check>
          <Check>You: update the pricing page and the FAQ</Check>
          <Check done>Send Maya the draft email</Check>
        </div>
      </div>
    </div>
  )
}
