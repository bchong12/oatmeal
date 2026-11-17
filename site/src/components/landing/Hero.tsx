// Hero, Notion-style: a big ink headline with one pastel pill in it, two buttons, and the app with
// Oatmeal's face peeking over the top and an Open Peeps friend peeking from behind its left edge.
// From the Purist frames "Capture · 1 Start" (type, pill, frame) and notion.com's hero (read as code).

import { Link } from '@tanstack/react-router'
import { useBrand } from '#/lib/brand'
import { Face } from '#/components/site/Mark'
import { AppShot } from './AppShot'
import { MacCta } from './shared'

/** The pastel pill with a dot that sits inside a headline, like Notion's "● Build". */
export function Highlight({ children, tone = 'honey' }: { children: React.ReactNode; tone?: 'honey' | 'blue' | 'green' | 'red' }) {
  const tones = {
    honey: ['bg-[#FCEBC2]', 'bg-[#F2B43A]'],
    blue: ['bg-[#DDEBF1]', 'bg-[#2F80ED]'],
    green: ['bg-[#DBEDDB]', 'bg-[#4DAB6F]'],
    red: ['bg-[#FDE2DD]', 'bg-[#EB5757]'],
  }[tone]
  return (
    <span className={`inline-flex items-center gap-[0.18em] rounded-full px-[0.32em] pt-[0.04em] pb-[0.08em] align-baseline text-[0.78em] font-medium tracking-[-0.02em] ${tones[0]}`}>
      <span className={`h-[0.34em] w-[0.34em] shrink-0 self-center rounded-full ${tones[1]}`} />
      {children}
    </span>
  )
}

export function Hero() {
  const brand = useBrand()
  return (
    <section className="relative px-5 pt-[64px] pb-[64px] sm:pt-[96px] sm:pb-[96px]">
      <div className="oat-rise mx-auto flex max-w-[980px] flex-col items-center gap-[14px] text-center">
        <h1 className="font-serif text-[clamp(44px,7.4vw,96px)] leading-[1.04] tracking-[-0.045em] text-black/95 [text-wrap:balance]">
          Say it once. <Highlight>It's</Highlight> written.
        </h1>
        <p className="max-w-[600px] text-[18px] leading-[27px] text-black/80 sm:text-[20px] sm:leading-[28px]">
          Talk into any app and it's typed. Hang up a call and the notes are already there. One free Mac app.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-[12px] pt-[8px]">
          <MacCta label={`Get ${brand.name} free`} />
          <Link to="/pricing" className="inline-flex min-h-[42px] items-center rounded-[8px] bg-[#F1F1EF] px-[18px] text-[16px] font-medium transition-colors hover:bg-[#E9E9E7]">
            See pricing
          </Link>
        </div>
        <span className="text-[14px] text-black/50">Free · macOS 26 or later · Runs on your Mac</span>
      </div>

      <div className="relative mx-auto mt-[48px] max-w-[1200px] sm:mt-[64px]">
        {/* The drawings sit behind the window, so only the part over its edge shows. */}
        <Face className="absolute -top-[86px] right-[6%] hidden h-[120px] w-[120px] rotate-[8deg] sm:block" />
        <img
          src="/peeps/peep-hands.svg"
          alt=""
          aria-hidden
          className="absolute top-[38%] -left-[96px] hidden h-[210px] w-auto min-[1300px]:block"
        />
        <AppShot className="relative" />
      </div>
    </section>
  )
}
