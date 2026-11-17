// Hero, Notion-style: a big two-line ink headline with one pastel pill in it whose word follows the
// demo below (types it / writes it up / records it), two buttons, then the app playing a short demo of
// each feature with a tab bar under it. Headline and pill measured from notion.com's hero (read as code):
// 96px semibold, -0.048em, pill at 0.75em with baseline alignment and even padding.

import { useEffect, useState } from 'react'
import { useBrand } from '#/lib/brand'
import { DEMO_TABS, HeroDemo, type DemoTab, type Tone } from './AppShot'
import { MacCta } from './shared'

const TONES: Record<Tone | 'green', [string, string]> = {
  honey: ['#FCEBC2', '#F2B43A'],
  blue: ['#DDEBF1', '#2F80ED'],
  green: ['#DBEDDB', '#4DAB6F'],
  red: ['#FDE2DD', '#EB5757'],
}

/** The pastel pill with a dot that sits inside a headline, like Notion's "● Build". Its text sits on the
 *  line's baseline, so the words read straight across. */
export function Highlight({ children, tone = 'honey' }: { children: React.ReactNode; tone?: Tone | 'green' }) {
  const [bg, dot] = TONES[tone]
  return (
    // Inter leaves more room above letters than below, so a smaller word on the line's baseline looks low.
    // Lifting the pill a touch centres it on the line: as much pill above the big capitals as below the
    // baseline, and the word sits in the middle of the pill.
    <span
      className="relative -top-[0.065em] inline-flex items-baseline gap-[0.2em] rounded-full px-[0.36em] py-[0.07em] align-baseline text-[0.84em] leading-[1.21] font-semibold tracking-[-0.03em] transition-colors duration-300"
      style={{ background: bg }}
    >
      <span className="h-[0.34em] w-[0.34em] shrink-0 self-center rounded-full transition-colors duration-300" style={{ background: dot }} />
      {children}
    </span>
  )
}

/** The pill whose word follows the demo. Like notion.com's, it deletes the old word and types the new
 *  one letter by letter, and the pill grows and shrinks with it. */
function TypedPill({ index }: { index: number }) {
  const target = DEMO_TABS[index]
  const [text, setText] = useState(target.verb)
  const [tone, setTone] = useState<Tone>(target.tone)
  const [typing, setTyping] = useState(false)
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      setText(target.verb)
      setTone(target.tone)
      return
    }
    let cur = text
    if (cur === target.verb) return
    setTyping(true)
    const id = window.setInterval(() => {
      if (!target.verb.startsWith(cur)) cur = cur.slice(0, -1)
      else cur = target.verb.slice(0, cur.length + 1)
      if (cur === '') setTone(target.tone)
      setText(cur)
      if (cur === target.verb) {
        clearInterval(id)
        setTyping(false)
      }
    }, 48)
    return () => clearInterval(id)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [index])
  return (
    <Highlight tone={tone}>
      <span className="inline-flex items-baseline whitespace-nowrap">
        {text}
        <span className={`ml-[0.04em] inline-block h-[0.78em] w-[0.06em] translate-y-[0.1em] rounded-full bg-current ${typing ? 'opacity-70' : 'opacity-0'}`} />
      </span>
    </Highlight>
  )
}

export function Hero() {
  const brand = useBrand()
  const [tab, setTab] = useState<DemoTab>('flow')
  const [playing, setPlaying] = useState(true)
  const index = DEMO_TABS.findIndex((t) => t.id === tab)

  // Move on to the next demo by itself; a click picks one and the cycle carries on from there.
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return setPlaying(false)
    if (!playing) return
    if (import.meta.env.DEV && (window as unknown as { __oatPhase?: number }).__oatPhase != null) return
    const id = window.setTimeout(() => setTab(DEMO_TABS[(index + 1) % DEMO_TABS.length].id), DEMO_TABS[index].ms)
    return () => clearTimeout(id)
  }, [tab, playing, index])

  return (
    <section className="relative px-5 pt-[56px] pb-[64px] sm:pt-[88px] sm:pb-[96px]">
      {/* Two Open Peeps either side of the subtitle and buttons, facing in, fading out at the waist so the
          drawing's crop never shows. Wide screens only. */}
      <div aria-hidden className="pointer-events-none absolute inset-x-0 top-[300px] mx-auto hidden h-[230px] max-w-[1320px] min-[1280px]:block">
        <img
          src="/peeps/peep-hands.svg"
          alt=""
          className="oat-float absolute bottom-0 left-[3%] h-[220px] w-auto"
          style={{ maskImage: 'linear-gradient(to bottom, #000 62%, transparent 96%)', WebkitMaskImage: 'linear-gradient(to bottom, #000 62%, transparent 96%)' }}
        />
        <img
          src="/peeps/peep-coffee.svg"
          alt=""
          className="oat-float absolute right-[3%] bottom-0 h-[220px] w-auto -scale-x-100 [animation-delay:-0.7s]"
          style={{ maskImage: 'linear-gradient(to bottom, #000 62%, transparent 96%)', WebkitMaskImage: 'linear-gradient(to bottom, #000 62%, transparent 96%)' }}
        />
      </div>
      <div className="oat-rise mx-auto flex max-w-[1240px] flex-col items-center gap-[18px] text-center">
        <h1 className="max-w-[1180px] font-serif text-[clamp(44px,6.7vw,96px)] leading-[1.2] font-semibold tracking-[-0.048em] text-black/95 [text-wrap:balance]">
          <span className="sr-only">Say it once. {brand.name} types it, writes it up and records it for you.</span>
          <span aria-hidden>
            Say it once. {brand.name} <TypedPill index={index} /> for you.
          </span>
        </h1>
        <p className="max-w-[640px] text-[18px] leading-[27px] text-black/75 sm:text-[20px] sm:leading-[29px]">
          Talk into any app and it’s typed. Hang up a call and the notes are written. Record your screen for your agent. One free Mac app.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-[12px] pt-[6px]">
          <MacCta label={`Get ${brand.name} free`} />
          <a
            href="https://github.com/bchong12/oatmeal"
            target="_blank"
            rel="noreferrer"
            className="inline-flex min-h-[42px] items-center gap-[8px] rounded-[8px] bg-[#F1F1EF] px-[18px] text-[16px] font-medium transition-colors hover:bg-[#E9E9E7]"
          >
            <svg viewBox="0 0 24 24" className="h-[16px] w-[16px]" aria-hidden><path fill="currentColor" d="M12 .5C5.7.5.5 5.7.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.3.8-.6v-2c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.3-1.7-1.3-1.7-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.6.2 2.8.1 3.1.8.8 1.2 1.8 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A11.5 11.5 0 0 0 23.5 12C23.5 5.7 18.3.5 12 .5Z" /></svg>
            Open source on GitHub
          </a>
        </div>
        <span className="text-[14px] text-black/50">Free · macOS 26 or later · Runs on your Mac</span>
      </div>

      <div className="mx-auto mt-[48px] max-w-[1200px] sm:mt-[64px]">
        <HeroDemo
          tab={tab}
          playing={playing}
          onTab={(t) => {
            setTab(t)
            setPlaying(true)
          }}
        />
      </div>
    </section>
  )
}
