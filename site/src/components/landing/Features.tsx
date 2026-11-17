// Flow, Notes and Capture as Notion-style feature cards: a grey header with a small label, a bold line and
// a round arrow, over a grey well holding a little white piece of the app. Card anatomy from notion.com
// ("Bring everything into one system of record", read as code); the Capture card from the Purist frames.

import { Link } from '@tanstack/react-router'
import { Face } from '#/components/site/Mark'
import { SLACK } from './logos'
import { Bars, Svg } from './shared'

function Card({ id, label, title, children }: { id: string; label: string; title: string; children: React.ReactNode }) {
  return (
    <article id={id} className="flex scroll-mt-[100px] flex-col overflow-hidden rounded-[12px] bg-[#F9F9F8]">
      <header className="flex flex-col gap-[8px] p-[24px]">
        <span className="text-[14px] text-black/60">{label}</span>
        <div className="flex items-end gap-[12px]">
          <h3 className="text-[22px] leading-[28px] font-bold [text-wrap:balance]">{title}</h3>
          <Link
            to="/download"
            aria-label="Get Oatmeal"
            className="ml-auto flex h-[32px] w-[32px] shrink-0 items-center justify-center rounded-full bg-black text-[18px] font-semibold text-white"
          >
            →
          </Link>
        </div>
      </header>
      <div className="relative flex aspect-[4/3] items-end justify-center overflow-hidden px-[24px] pt-[24px]">{children}</div>
    </article>
  )
}

/** The white sheet a card's picture sits on: rounded at the top, running off the bottom. */
function Sheet({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return (
    <div
      className={`flex w-full flex-col gap-[12px] rounded-t-[12px] bg-white p-[20px] text-[14px] leading-[21px] shadow-[rgba(0,0,0,0.01)_0_0_1px,rgba(0,0,0,0.02)_0_0_2px,rgba(0,0,0,0.027)_0_2px_7px,rgba(0,0,0,0.04)_0_4px_18px] ${className}`}
    >
      {children}
    </div>
  )
}

function FlowPicture() {
  return (
    <>
      <Sheet className="h-[86%]">
        <div className="flex items-center gap-[8px] text-[13px] font-semibold">
          <Svg html={SLACK} viewBox="0 0 24 24" className="h-[16px] w-[16px]" />
          #pricing
        </div>
        <div className="flex gap-[10px]">
          <span className="flex h-[30px] w-[30px] shrink-0 items-end justify-center overflow-hidden rounded-[8px] bg-[#FCEBC2]">
            <Face className="h-[34px] w-[34px]" />
          </span>
          <div className="flex flex-col">
            <span className="text-[13px] font-semibold">You</span>
            <span className="text-black/80">
              Can you ask Maya on Friday whether the pricing email went out?<span className="ml-[1px] inline-block h-[16px] w-[2px] translate-y-[3px] bg-ink" />
            </span>
          </div>
        </div>
        <div className="mt-auto mb-[44px] rounded-[8px] border border-black/10 px-[12px] py-[9px] text-[13px] text-black/40">
          “so um can you check if the pricing email… actually just ask Maya on Friday”
        </div>
      </Sheet>
      {/* Flow's pill, as it floats over any app (Dayform's pill, kept as it is). */}
      <div className="absolute bottom-[14px] left-1/2 flex h-[40px] -translate-x-1/2 items-center gap-[10px] rounded-full bg-[rgba(24,25,28,0.96)] px-[14px] shadow-[0_10px_24px_rgba(0,0,0,0.22)]">
        <span className="text-[12px] font-medium whitespace-nowrap text-white/70">Hold right ⌥</span>
        <Bars heights={[6, 14, 22, 12, 24, 16, 8]} />
      </div>
    </>
  )
}

function NotesPicture() {
  return (
    <Sheet className="h-[86%]">
      <div className="flex flex-col gap-[2px]">
        <span className="text-[12px] text-black/45">Today, 10:00 am · 32 min · no bot joined</span>
        <span className="text-[18px] font-bold tracking-[-0.3px]">Pricing review with Maya</span>
      </div>
      <div className="flex flex-col gap-[4px]">
        <span className="text-[13px] font-semibold">Summary</span>
        <span className="h-[7px] w-[92%] rounded-full bg-[#EFEFED]" />
        <span className="h-[7px] w-[78%] rounded-full bg-[#EFEFED]" />
        <span className="h-[7px] w-[64%] rounded-full bg-[#EFEFED]" />
      </div>
      <div className="flex flex-col gap-[6px]">
        <span className="text-[13px] font-semibold">Next steps</span>
        <span className="flex items-center gap-[8px] text-[13px]">
          <span className="h-[13px] w-[13px] shrink-0 rounded-[3px] border border-[#D3D1CB]" />
          Maya: confirm the email went out, <span className="rounded-[4px] bg-[#FCEBC2] px-[4px]">Friday</span>
        </span>
        <span className="flex items-center gap-[8px] text-[13px]">
          <span className="h-[13px] w-[13px] shrink-0 rounded-[3px] border border-[#D3D1CB]" />
          You: update the pricing page
        </span>
      </div>
    </Sheet>
  )
}

function CapturePicture() {
  return (
    <>
      <Sheet className="h-[86%] gap-[10px]">
        <span className="text-[15px] font-semibold">Payment method</span>
        <div className="flex justify-between border-t border-[#EFEFED] pt-[8px] text-[13px] text-black/60">
          <span>Visa ending 4242</span>
          <span className="rounded-[4px] bg-[#FCEBC2] px-[5px] font-semibold text-[#C4554D]">Card declined</span>
        </div>
        <div className="flex justify-between border-t border-[#EFEFED] pt-[8px] text-[13px] text-black/60">
          <span>Billing email</span>
          <span>finance@acme.com</span>
        </div>
        <div className="pointer-events-none absolute inset-x-[36px] top-[36px] bottom-0 rounded-[4px] border-[1.5px] border-dashed border-live" />
      </Sheet>
      <span className="absolute bottom-[20px] left-[36px] flex h-[72px] w-[72px] items-end justify-center overflow-hidden rounded-full border-[3px] border-white bg-[#FCEBC2] shadow-[0_8px_20px_rgba(0,0,0,0.18)]">
        <Face className="h-[80px] w-[80px]" />
      </span>
      <span className="absolute right-[36px] bottom-[26px] flex items-center gap-[8px] rounded-[10px] border border-black/10 bg-white px-[12px] py-[7px] text-[13px] font-medium shadow-[0_6px_16px_rgba(0,0,0,0.08)]">
        <span className="h-[8px] w-[8px] rounded-full bg-live shadow-[0_0_0_4px_rgba(235,87,87,0.18)]" />
        0:42
        <span className="rounded-[6px] bg-ink px-[8px] py-[2px] text-white">Stop</span>
      </span>
    </>
  )
}

export function Features() {
  return (
    <section className="oat-enter mx-auto flex max-w-[1240px] flex-col gap-[40px] px-5 pb-[64px] sm:gap-[48px] sm:pb-[96px]">
      <div className="flex flex-col items-center gap-[12px] text-center">
        <h2 className="font-serif text-[clamp(32px,4.4vw,48px)] leading-[1.1] tracking-[-0.035em]">Three things. One app.</h2>
        <p className="max-w-[560px] text-[18px] leading-[27px] text-black/70">Everything runs on your Mac. Nothing joins your calls.</p>
      </div>
      <div className="grid gap-[24px] md:grid-cols-2 lg:grid-cols-3">
        <Card id="flow" label="Flow · dictation" title="Talk, and it's typed in any app.">
          <FlowPicture />
        </Card>
        <Card id="notes" label="Notes · meetings" title="Every call, written up by your AI.">
          <NotesPicture />
        </Card>
        <Card id="capture" label="Capture · screen and face" title="Show it with your face and voice.">
          <CapturePicture />
        </Card>
      </div>
    </section>
  )
}
