// "Works with every AI you already use": the AIs that write your notes on the left, the mark in the
// middle, and every MCP app that can ask your meetings on the right. Solid hairlines carry honey beams.
// Purist node Psm1qy.

import { useBrand } from '#/lib/brand'
import { Stage, Svg, at, useInViewOnce, useSvgReducedMotion } from './shared'

const WIRES_IN = [
  'M 310 106 C 430 106, 430 260, 538 260',
  'M 310 196 C 430 196, 440 260, 538 260',
  'M 310 286 C 430 286, 440 260, 538 260',
  'M 310 376 C 430 376, 430 260, 538 260',
]
const WIRES_OUT = [
  'M 662 260 C 760 260, 760 108, 836 108',
  'M 662 260 C 760 260, 770 218, 836 218',
  'M 662 260 C 760 260, 770 328, 836 328',
  'M 662 260 C 760 260, 760 438, 836 438',
]

// The design's wiring (node Pzih50), 1200×520: hairlines, and a honey beam travelling each one.
const WIRES = `
  <g fill="none" stroke="rgba(28,25,21,0.16)" stroke-width="1.5">${[...WIRES_IN, ...WIRES_OUT].map((d) => `<path d="${d}"></path>`).join('')}</g>
  <g fill="none" stroke="#D99A2B" stroke-width="3" stroke-linecap="round" stroke-dasharray="34 420">
    ${WIRES_IN.map((d, i) => `<path d="${d}"><animate attributeName="stroke-dashoffset" from="454" to="0" dur="2.2s" begin="${i * 0.5}s" repeatCount="indefinite"></animate></path>`).join('')}
    ${WIRES_OUT.map((d, i) => `<path d="${d}"><animate attributeName="stroke-dashoffset" from="454" to="0" dur="2s" begin="${0.2 + i * 0.5}s" repeatCount="indefinite"></animate></path>`).join('')}
  </g>
`

// Phone and tablet: one short vertical hairline with its beam, between writers → mark → apps.
const LINK = (begin: number) => `
  <path d="M 2 0 V 56" fill="none" stroke="rgba(28,25,21,0.16)" stroke-width="1.5"></path>
  <path d="M 2 0 V 56" fill="none" stroke="#D99A2B" stroke-width="3" stroke-linecap="round" stroke-dasharray="14 70"><animate attributeName="stroke-dashoffset" from="84" to="0" dur="1.6s" begin="${begin}s" repeatCount="indefinite"></animate></path>
`

const APPS = [
  { name: 'Claude', logo: 'claude' },
  { name: 'ChatGPT', logo: 'openai' },
  { name: 'Cursor', logo: 'cursor' },
  { name: 'Gemini', logo: 'gemini' },
  { name: 'Perplexity', logo: 'perplexity' },
  { name: 'Raycast', logo: 'raycast' },
  { name: 'Windsurf', logo: 'windsurf' },
  { name: 'Copilot', logo: 'copilot' },
  { name: 'Zed', logo: 'zed' },
  { name: 'Le Chat', logo: 'lechat' },
  { name: 'n8n', logo: 'n8n' },
]

function Label({ children, className = '', style }: { children: React.ReactNode; className?: string; style?: React.CSSProperties }) {
  return (
    <span className={`text-[12px] font-bold tracking-[1px] text-ink/50 uppercase ${className}`} style={style}>
      {children}
    </span>
  )
}

function Writer({ logo, name, note, noteClass, ours }: { logo: string; name: string; note: string; noteClass: string; ours?: boolean }) {
  return (
    <div
      className={`flex h-[72px] items-center gap-[14px] rounded-[16px] border px-[16px] shadow-[0_1px_2px_rgba(28,25,21,0.05)] ${
        ours ? 'border-ink bg-honey' : 'border-line bg-white'
      }`}
    >
      <img src={`/landing/${logo}.png`} alt="" className="h-[42px] w-[42px] shrink-0" />
      <div className="flex flex-1 flex-col gap-[2px]">
        <span className="text-[16px] font-bold">{name}</span>
        <span className={`text-[13px] font-medium ${noteClass}`}>{note}</span>
      </div>
    </div>
  )
}

function MobileLink({ begin }: { begin: number }) {
  return <Svg html={LINK(begin)} viewBox="0 0 4 56" width={4} height={56} className="oat-mobile self-center" />
}

export function YourAI() {
  const brand = useBrand()
  const svgRoot = useSvgReducedMotion<HTMLElement>()
  const [gridRef, gridIn] = useInViewOnce<HTMLDivElement>()
  return (
    <section
      ref={svgRoot}
      id="your-ai"
      className="oat-enter mx-auto flex max-w-[1440px] scroll-mt-[100px] flex-col items-center gap-10 px-5 pt-10 pb-20 sm:gap-[48px] min-[1200px]:pb-[130px]"
    >
      <div className="flex flex-col items-center gap-[18px] text-center">
        <span className="text-[14px] font-semibold tracking-[1px] text-ink/65 uppercase">Your AI, your notes</span>
        <h2 className="flex flex-col items-center font-serif font-normal tracking-[-0.035em] text-[clamp(34px,6vw,72px)] leading-[1.06]">
          <span>Works with every AI</span>
          <span className="text-umber">you already use</span>
        </h2>
        <p className="max-w-[600px] text-[17px] leading-[25px] font-medium text-ink/75 sm:text-[19px] sm:leading-[27px]">
          Your notes are written by the AI you already pay for. Then any app that speaks MCP can search every meeting you've had.
        </p>
      </div>

      <Stage w={1200} h={520} className="mx-auto max-w-[520px]" innerClassName="flex flex-col gap-4">
        <Svg html={WIRES} viewBox="0 0 1200 520" width={1200} height={520} className="oat-desktop absolute top-0 left-0" />

        <Label className="oat-abs" style={at(0, 30)}>
          Writes your notes with
        </Label>
        <div className="oat-abs flex flex-col gap-[12px] min-[1200px]:gap-[18px]" style={at(0, 70, 310)}>
          <Writer logo="claude" name="Claude Code" note="Found on this Mac" noteClass="text-good" />
          <Writer logo="openai" name="Codex" note="On your ChatGPT plan" noteClass="text-ink/55" />
          <Writer logo="gemini" name="Gemini CLI" note="On your Google account" noteClass="text-ink/55" />
          <Writer logo="oatmeal" name={`${brand.name} AI`} note="Nothing to install · Pro" noteClass="text-ink/70" ours />
        </div>

        <MobileLink begin={0} />
        <div
          className="oat-abs oat-breathe my-4 flex h-[124px] w-[124px] items-center justify-center self-center rounded-[34px] bg-umber shadow-[0_0_0_12px_rgba(246,210,124,0.45),0_0_0_26px_rgba(246,210,124,0.18),0_24px_48px_rgba(28,25,21,0.25)] min-[1200px]:my-0"
          style={at(538, 198, 124, 124)}
        >
          <img src="/landing/oatmeal.png" alt="" className="h-[124px] w-[124px]" />
        </div>
        <MobileLink begin={0.6} />

        <Label className="oat-abs" style={at(846, 30)}>
          Ask your meetings from
        </Label>
        <div
          ref={gridRef}
          data-in={gridIn || undefined}
          className="oat-abs oat-reveal grid grid-cols-3 gap-[10px] sm:gap-[14px] min-[1200px]:grid-cols-[repeat(3,108px)]"
          style={at(846, 60, 354)}
        >
          {APPS.map((app, i) => (
            <div
              key={app.name}
              className="flex h-[96px] flex-col items-center justify-center gap-[7px] rounded-[16px] border border-ink/10 bg-white"
              style={{ '--anim': `oat-pop-in 0.45s cubic-bezier(0.34,1.56,0.64,1) ${i * 0.05}s` } as React.CSSProperties}
            >
              <img src={`/landing/${app.logo}.png`} alt="" className="h-[40px] w-[40px]" />
              <span className="text-[12px] font-semibold">{app.name}</span>
            </div>
          ))}
          <div
            className="flex h-[96px] flex-col items-center justify-center gap-[4px] rounded-[16px] border-[1.5px] border-dashed border-ink/25"
            style={{ '--anim': `oat-pop-in 0.45s cubic-bezier(0.34,1.56,0.64,1) ${APPS.length * 0.05}s` } as React.CSSProperties}
          >
            <span className="font-serif text-[22px]">+ any</span>
            <span className="text-[12px] font-semibold text-ink/60">MCP app</span>
          </div>
        </div>
      </Stage>
    </section>
  )
}
