// Notes: "Meetings that write themselves". A call on the left, the notes writing themselves on the right,
// and the three things that make it different underneath. Purist node Prq1qy.

import { useBrand } from '#/lib/brand'
import { CLAUDE_BURST, LUCIDE, ZOOM_CAMERA } from './logos'
import { Eyebrow, Stage, Svg, at, useInViewOnce, useSvgReducedMotion } from './shared'

// The dotted hand-off from the call to the notes (node Pxe075), 200×200.
const HANDOFF = `<path d="M 8 100 C 70 100, 100 40, 192 40" fill="none" stroke="#F6D27C" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="2 10"><animate attributeName="stroke-dashoffset" from="24" to="0" dur="0.8s" repeatCount="indefinite"></animate></path><path d="M 8 100 C 70 100, 100 160, 192 160" fill="none" stroke="#F6D27C" stroke-width="2.5" stroke-linecap="round" stroke-dasharray="2 10"><animate attributeName="stroke-dashoffset" from="24" to="0" dur="0.8s" repeatCount="indefinite"></animate></path>`

const TRANSCRIPT = [
  { who: 'Maya', you: false, text: 'If Pro goes to fourteen, do current customers move too?' },
  { who: 'You', you: true, text: 'Not until March. They keep twelve till then.' },
  { who: 'Maya', you: false, text: "Okay. I'll write the email by Friday." },
]

const NOTE_LINES: { text: string; head?: boolean; gap?: boolean }[] = [
  { text: 'New plans', head: true },
  { text: '• Pro goes from $12 to $14 on January 1' },
  { text: '• Current customers keep $12 until March' },
  { text: 'Next steps', head: true, gap: true },
  { text: '☐ Maya: price-change email by Friday' },
  { text: '☐ Dev: day-25 reminder on Free' },
]

const FEATURES = [
  { icon: LUCIDE.botOff, title: 'No bot in the call', body: 'It listens on your Mac. Nobody gets a weird invite.' },
  { icon: LUCIDE.sparkles, title: 'Written when you hang up', body: 'Topics, decisions and next steps, built around what you jotted.' },
  { icon: LUCIDE.search, title: 'Ask any meeting later', body: '"What did Maya promise?" Ask from Claude, ChatGPT or Cursor.' },
]

function CallWindow() {
  const [ref, inView] = useInViewOnce<HTMLDivElement>()
  return (
    <div
      className="oat-abs flex flex-col overflow-hidden rounded-[16px] border border-white/10 bg-[#141210] shadow-[0_30px_60px_rgba(0,0,0,0.35)]"
      style={at(56, 64, 500, 420)}
    >
      <div className="flex items-center justify-between px-[14px] py-[12px]">
        <div className="flex gap-[6px]">
          <div className="h-[10px] w-[10px] rounded-full bg-[#ff5f57]" />
          <div className="h-[10px] w-[10px] rounded-full bg-[#febc2e]" />
          <div className="h-[10px] w-[10px] rounded-full bg-[#28c840]" />
        </div>
        <div className="flex items-center gap-[6px]">
          <div className="flex h-[16px] w-[16px] items-center justify-center rounded-[4px] bg-[#0B5CFF]">
            <Svg html={ZOOM_CAMERA} viewBox="0 0 24 24" className="h-[10px] w-[10px]" />
          </div>
          <span className="text-[12px] font-semibold text-white/70">Pricing review</span>
        </div>
      </div>
      <div className="flex gap-[6px] px-[10px]">
        {[
          { name: 'Maya', src: '/landing/maya.jpg', y: '30%' },
          { name: 'Dev', src: '/landing/dev.jpg', y: '35%' },
        ].map((p) => (
          <div
            key={p.name}
            className="relative h-[120px] flex-1 rounded-[10px] sm:h-[170px]"
            style={{ backgroundImage: `url(${p.src})`, backgroundSize: 'cover', backgroundPosition: `center ${p.y}` }}
          >
            <span className="absolute bottom-[8px] left-[8px] rounded-[5px] bg-black/55 px-[7px] py-[2px] text-[11px] text-white">{p.name}</span>
          </div>
        ))}
      </div>
      <div className="flex flex-1 flex-col gap-[10px] px-[18px] py-[16px]">
        <span className="text-[11px] font-semibold tracking-[1px] text-white/40 uppercase">Live transcript</span>
        <div ref={ref} data-in={inView || undefined} className="oat-reveal flex flex-col gap-[9px]">
          {TRANSCRIPT.map((line, i) => (
            <div key={i} className="flex gap-[10px]" style={{ '--anim': `oat-up-8 0.5s ease-out ${i * 0.5}s` } as React.CSSProperties}>
              <span className={`w-[38px] shrink-0 text-[13px] font-bold ${line.you ? 'text-white/55' : 'text-honey'}`}>{line.who}</span>
              <span className="text-[13px] leading-[18px] text-white/85">{line.text}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function NoteCard() {
  const [ref, inView] = useInViewOnce<HTMLDivElement>()
  return (
    <div
      className="oat-abs flex flex-col gap-[12px] rounded-[16px] border-[1.5px] border-ink bg-cream px-[24px] pt-[22px] pb-[26px] shadow-[5px_5px_0_var(--honey)]"
      style={at(720, 104, 430)}
    >
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-2">
        <span className="font-serif text-[24px] tracking-[-0.02em] whitespace-nowrap">Pricing review</span>
        <div className="flex items-center gap-[6px] rounded-full border border-line bg-white px-[10px] py-[5px]">
          <div className="flex h-[14px] w-[14px] items-center justify-center rounded-[4px] bg-[#D97757]">
            <Svg html={CLAUDE_BURST} viewBox="0 0 24 24" className="h-[9px] w-[9px]" />
          </div>
          <span className="text-[12px] font-semibold">Writing…</span>
        </div>
      </div>
      <span className="text-[13px] text-ink/55">Today, 2:00 PM · Maya, Dev, you</span>
      <div ref={ref} data-in={inView || undefined} className="oat-reveal flex flex-col gap-[8px] pt-[4px]">
        {NOTE_LINES.map((line, i) => (
          <span
            key={i}
            className={line.head ? `text-[14px] font-bold ${line.gap ? 'pt-[6px]' : ''}` : 'text-[15px] leading-[21px]'}
            style={{ '--anim': `oat-slide-8 0.45s ease-out ${1.2 + i * 0.22}s` } as React.CSSProperties}
          >
            {line.text}
          </span>
        ))}
      </div>
    </div>
  )
}

export function Notes() {
  const brand = useBrand()
  const svgRoot = useSvgReducedMotion<HTMLElement>()
  return (
    <section
      ref={svgRoot}
      id="notes"
      className="oat-enter mx-auto flex max-w-[1440px] scroll-mt-[100px] flex-col items-center gap-10 px-5 py-20 sm:gap-[56px] min-[1200px]:py-[130px]"
    >
      <div className="flex flex-col items-center gap-[18px] text-center">
        <Eyebrow className="text-ink/65">{brand.name} Notes</Eyebrow>
        <h2 className="flex flex-col items-center font-serif font-normal tracking-[-0.035em] text-[clamp(38px,7vw,84px)] leading-[1.05]">
          <span>Meetings that</span>
          <span className="text-umber">write themselves</span>
        </h2>
      </div>

      <Stage
        w={1200}
        h={590}
        innerClassName="flex flex-col gap-6 overflow-hidden rounded-[28px] p-4 sm:p-8 min-[1200px]:p-0"
        innerStyle={{
          background:
            'radial-gradient(55% 70% at 78% 30%, rgba(246,210,124,0.35) 0%, rgba(246,210,124,0) 70%), radial-gradient(50% 60% at 15% 90%, rgba(217,151,87,0.25) 0%, rgba(217,151,87,0) 70%), #3B2A20',
        }}
      >
        <CallWindow />
        <Svg html={HANDOFF} viewBox="0 0 200 200" className="oat-abs oat-desktop" style={at(548, 180, 200, 200)} />
        <NoteCard />
        <div
          className="oat-abs oat-float flex h-[44px] w-max items-center gap-[10px] self-center rounded-full border border-white/10 bg-[rgba(24,25,28,0.96)] pr-[6px] pl-[16px] shadow-[0_12px_28px_rgba(0,0,0,0.35)]"
          style={at(470, 520)}
        >
          <div className="oat-blink h-[9px] w-[9px] rounded-full bg-live" />
          <span className="text-[14px] font-bold text-white">23:14</span>
          <div className="flex h-[30px] items-center rounded-full bg-white/14 px-[12px]">
            <span className="text-[13px] font-semibold text-white">Meeting over? Save notes</span>
          </div>
        </div>
      </Stage>

      <div className="grid w-full max-w-[1200px] gap-8 md:grid-cols-3 md:gap-[24px]">
        {FEATURES.map((f) => (
          <div key={f.title} className="flex items-start gap-[14px]">
            <div className="flex h-[40px] w-[40px] shrink-0 items-center justify-center rounded-[12px] border-[1.5px] border-ink bg-honey">
              <svg
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="h-[18px] w-[18px]"
                aria-hidden
                dangerouslySetInnerHTML={{ __html: f.icon }}
              />
            </div>
            <div className="flex flex-col gap-[4px]">
              <span className="font-serif text-[22px] tracking-[-0.02em]">{f.title}</span>
              <span className="text-[15px] leading-[22px] text-ink/70">{f.body}</span>
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}
