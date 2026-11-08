// Hero: "Say it once. It's written." Words stream along a curve into the recording pill, then out along
// the dark Flow band (typed for you) and the honey Notes band (written up). Purist node Pps1qy.

import { useBrand } from '#/lib/brand'
import { Loop } from '#/components/site/Mark'
import { SLACK, ZOOM_CAMERA } from './logos'
import { Bars, MacCta, Stage, Svg, at, useSvgReducedMotion } from './shared'

const IN_TEXT =
  'so um, can you check if the pricing email went out… actually, just ask Maya on Friday · so um, can you check if the pricing email went out… actually, just ask Maya on Friday · '
const FLOW_TEXT = 'Can you ask Maya on Friday whether the pricing email went out? · Can you ask Maya on Friday whether the pricing email went out? · '
const NOTES_TEXT = 'Next step: Maya confirms the pricing email went out, Friday · Next step: Maya confirms the pricing email went out, Friday · '

// The design's word streams, 1440×400 (node Pvm075).
const STREAMS = `
  <defs>
    <path id="oat-in3" d="M -40 250 C 110 160, 250 290, 370 200 S 470 170, 490 170"></path>
    <path id="oat-flow3" d="M 632 170 C 720 170, 750 92, 862 92"></path>
    <path id="oat-notes3" d="M 632 170 C 720 170, 750 262, 862 262"></path>
  </defs>
  <text font-family="Figtree" font-weight="500" font-size="18" fill="rgba(28,25,21,0.45)"><textPath href="#oat-in3" startOffset="-620">${IN_TEXT}<animate attributeName="startOffset" from="-620" to="0" dur="9s" repeatCount="indefinite"></animate></textPath></text>
  <use href="#oat-flow3" fill="none" stroke="#3B2A20" stroke-width="30" stroke-linecap="round"></use>
  <text font-family="Figtree" font-weight="600" font-size="14" fill="#FCF8EA" dy="5"><textPath href="#oat-flow3" startOffset="-470">${FLOW_TEXT}<animate attributeName="startOffset" from="-470" to="0" dur="7s" repeatCount="indefinite"></animate></textPath></text>
  <use href="#oat-notes3" fill="none" stroke="#F6D27C" stroke-width="30" stroke-linecap="round"></use>
  <text font-family="Figtree" font-weight="600" font-size="14" fill="#1C1915" dy="5"><textPath href="#oat-notes3" startOffset="-440">${NOTES_TEXT}<animate attributeName="startOffset" from="-440" to="0" dur="7s" repeatCount="indefinite"></animate></textPath></text>
`

// Phone and tablet: the same streams, stacked. The words still flow in, and out along each band.
const M_IN = `
  <defs><path id="oat-in-m" d="M -40 78 C 50 20, 130 96, 236 52"></path></defs>
  <text font-family="Figtree" font-weight="500" font-size="16" fill="rgba(28,25,21,0.45)"><textPath href="#oat-in-m" startOffset="-620">${IN_TEXT}<animate attributeName="startOffset" from="-620" to="0" dur="9s" repeatCount="indefinite"></animate></textPath></text>
`
const band = (id: string, stroke: string, fill: string, text: string, from: number) => `
  <defs><path id="${id}" d="M 20 30 C 130 4, 270 56, 380 30"></path></defs>
  <use href="#${id}" fill="none" stroke="${stroke}" stroke-width="30" stroke-linecap="round"></use>
  <text font-family="Figtree" font-weight="600" font-size="14" fill="${fill}" dy="5"><textPath href="#${id}" startOffset="${from}">${text}<animate attributeName="startOffset" from="${from}" to="0" dur="7s" repeatCount="indefinite"></animate></textPath></text>
`
const M_FLOW = band('oat-flow-m', '#3B2A20', '#FCF8EA', FLOW_TEXT, -470)
const M_NOTES = band('oat-notes-m', '#F6D27C', '#1C1915', NOTES_TEXT, -440)

function Pill({ className = '', style }: { className?: string; style?: React.CSSProperties }) {
  return (
    <div
      className={`flex h-[44px] w-max items-center gap-[10px] rounded-full bg-[rgba(24,25,28,0.96)] px-[14px] shadow-[0_10px_24px_rgba(28,25,21,0.22)] ${className}`}
      style={style}
    >
      <div className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-[6px] bg-white">
        <Svg html={SLACK} viewBox="0 0 24 24" className="h-[14px] w-[14px]" />
      </div>
      <Bars
        heights={[6, 14, 22, 12, 26, 16, 8, 4]}
        colors={[
          'rgba(255,255,255,0.6)',
          'rgba(255,255,255,0.8)',
          '#fff',
          'rgba(255,255,255,0.75)',
          '#fff',
          'rgba(255,255,255,0.85)',
          'rgba(255,255,255,0.6)',
          'rgba(255,255,255,0.45)',
        ]}
      />
      <Loop width={22} color="rgba(255,255,255,0.55)" />
    </div>
  )
}

function FlowCard({ className = '', style }: { className?: string; style?: React.CSSProperties }) {
  return (
    <div
      className={`oat-slide flex flex-col gap-[8px] rounded-[14px] border-[1.5px] border-ink bg-white px-[18px] py-[16px] shadow-[3px_3px_0_var(--ink)] [animation-delay:1.7s] ${className}`}
      style={style}
    >
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
        <div className="flex items-center gap-[8px]">
          <Svg html={SLACK} viewBox="0 0 24 24" className="h-[16px] w-[16px] shrink-0" />
          <span className="text-[13px] font-bold">Message to Dev</span>
        </div>
        <span className="text-[12px] font-semibold whitespace-nowrap text-ink/50">FLOW · TYPED FOR YOU</span>
      </div>
      <span className="text-[16px] leading-[23px]">Can you ask Maya on Friday whether the pricing email went out?</span>
    </div>
  )
}

function NotesCard({ className = '', style }: { className?: string; style?: React.CSSProperties }) {
  return (
    <div
      className={`oat-slide flex flex-col gap-[8px] rounded-[14px] border-[1.5px] border-ink bg-white px-[18px] py-[16px] shadow-[3px_3px_0_var(--ink)] [animation-delay:1.9s] ${className}`}
      style={style}
    >
      <div className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
        <div className="flex items-center gap-[8px]">
          <div className="flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-[5px] bg-[#0B5CFF]">
            <Svg html={ZOOM_CAMERA} viewBox="0 0 24 24" className="h-[12px] w-[12px]" />
          </div>
          <span className="font-serif text-[17px] tracking-[-0.02em]">Pricing review with Maya</span>
        </div>
        <span className="text-[12px] font-semibold whitespace-nowrap text-ink/50">NOTES · WRITTEN UP</span>
      </div>
      <span className="text-[13px] font-bold">Next steps</span>
      <span className="text-[15px] leading-[21px]">☐ Maya: confirm the pricing email went out, Friday</span>
    </div>
  )
}

export function Hero() {
  const brand = useBrand()
  const svgRoot = useSvgReducedMotion<HTMLElement>()
  return (
    <section ref={svgRoot} className="relative overflow-hidden pb-16 min-[1200px]:h-[1010px] min-[1200px]:pb-0">
      {/* Copy: eyebrow, headline, line, button and small print rise in one after another. */}
      <div className="oat-rise flex flex-col items-center gap-[22px] px-5 pt-[72px] text-center sm:gap-[26px] min-[1200px]:pt-[110px]">
        <span className="text-[13px] font-semibold tracking-[1px] text-ink/65 uppercase sm:text-[14px]">{brand.name} Flow + Notes</span>
        <h1 className="flex flex-col items-center font-serif font-normal tracking-[-0.035em] text-[clamp(50px,8vw,96px)] leading-[1.02]">
          <span>Say it once.</span>
          <span className="relative flex">
            <span
              aria-hidden
              className="oat-wipe absolute rounded-[6px] bg-honey"
              style={{ left: '-0.083em', top: '0.52em', width: '5.21em', height: '0.396em', transform: 'rotate(-1.5deg)', transformOrigin: '0% 50%' }}
            />
            <span className="relative">It's written.</span>
          </span>
        </h1>
        <p className="max-w-[520px] text-[18px] leading-[26px] font-medium sm:text-[20px] sm:leading-[28px]">
          Talk into any app and Flow types it. Hang up a call and Notes has already written it up. One free Mac app.
        </p>
        <MacCta label={`Get ${brand.name} for Mac`} />
        <span className="text-[14px] text-ink/60">Free · macOS 14 or later · Runs on your Mac</span>
      </div>

      {/* Desktop: the design's 1440×400 stream art, scaled to fit. */}
      <div className="oat-desktop absolute inset-x-0 top-[610px]">
        <Stage w={1440} h={400}>
          <Svg html={STREAMS} viewBox="0 0 1440 400" width={1440} height={400} className="absolute top-0 left-0 overflow-visible" />
          <Pill className="oat-abs" style={at(486, 148)} />
          <FlowCard className="oat-abs" style={at(866, 42, 420)} />
          <NotesCard className="oat-abs" style={at(866, 210, 420)} />
        </Stage>
      </div>

      {/* Phone and tablet: words in, pill, then each band and what it became. */}
      <div className="oat-mobile mx-auto mt-14 flex w-full max-w-[460px] flex-col px-4">
        <div className="relative">
          <Svg html={M_IN} viewBox="0 0 400 100" className="block h-auto w-full overflow-visible" />
          <Pill className="absolute top-[52%] left-[57%] -translate-y-1/2" />
        </div>
        <Svg html={M_FLOW} viewBox="0 0 400 60" className="mt-3 block h-auto w-full" />
        <FlowCard className="mt-2" />
        <Svg html={M_NOTES} viewBox="0 0 400 60" className="mt-5 block h-auto w-full" />
        <NotesCard className="mt-2" />
      </div>
    </section>
  )
}
