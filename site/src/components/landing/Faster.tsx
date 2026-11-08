// Flow: "Talk 3x faster than you type", on espresso. Typing at 40 wpm beside talking at 150 wpm, where
// the words stream across a blurred photo. Purist node Pqz1qy.

import { gmail, googleMeet, notion, slackMono, zoomWordmark } from './logos'
import { Bars, Svg, useSvgReducedMotion } from './shared'

const LOGO = 'rgba(252,248,234,0.7)'

const TALK_TEXT =
  "give me a sec… alright, the pricing doc is ready. want to walk me through what's changing for Pro? · give me a sec… alright, the pricing doc is ready. want to walk me through what's changing for Pro? · "

// The design's stream across the talking card, 880×200 (node Pwl075).
const TALK_STREAM = `<defs><path id="oat-talk2" d="M -40 120 C 160 40, 380 40, 520 90 S 780 150, 940 70"></path></defs><text font-family="Figtree" font-weight="600" font-size="19" fill="#fff"><textPath href="#oat-talk2" startOffset="-860">${TALK_TEXT}<animate attributeName="startOffset" from="-860" to="0" dur="11s" repeatCount="indefinite"></animate></textPath></text>`

const APPS = [
  { name: 'Slack', svg: slackMono(LOGO) },
  { name: 'Gmail', svg: gmail(LOGO) },
  { name: 'Notion', svg: notion(LOGO) },
  { name: 'Google Meet', svg: googleMeet(LOGO) },
]

export function Faster() {
  const svgRoot = useSvgReducedMotion<HTMLElement>()
  return (
    <section
      ref={svgRoot}
      id="flow"
      className="oat-enter flex scroll-mt-[100px] flex-col items-center gap-10 bg-espresso px-5 pt-20 pb-20 sm:gap-[48px] min-[1200px]:pt-[110px] min-[1200px]:pb-[120px]"
    >
      <div className="flex flex-col items-center gap-[20px] text-center">
        <h2 className="flex flex-wrap justify-center gap-x-[0.26em] font-serif font-normal tracking-[-0.035em] text-cream text-[clamp(40px,7vw,84px)] leading-[1.05]">
          <span>Talk 3x faster</span>
          <span className="text-honey">than you type</span>
        </h2>
        <p className="max-w-[560px] text-[17px] leading-[25px] font-medium text-cream/75 sm:text-[19px] sm:leading-[27px]">
          Hold Right ⌥ and talk. Flow types it into Slack, Mail, Notion or your code editor, cleaned up and ready to send.
        </p>
        <div className="flex flex-wrap items-center justify-center gap-x-[40px] gap-y-4 pt-[4px]">
          <span className="w-full text-[13px] font-semibold tracking-[1px] text-cream/45 uppercase sm:w-auto">Works in</span>
          {APPS.map((app) => (
            <div key={app.name} className="flex items-center gap-[9px]">
              <Svg html={app.svg} viewBox="0 0 24 24" className="h-[22px] w-[22px]" />
              <span className="text-[16px] font-semibold text-cream/70">{app.name}</span>
            </div>
          ))}
          <Svg html={zoomWordmark(LOGO)} viewBox="0 7 24 10" className="h-[22px] w-[52px]" />
        </div>
      </div>

      <div className="flex w-full max-w-[1200px] flex-col gap-[20px] min-[900px]:h-[440px] min-[900px]:flex-row">
        {/* Typing: slow, and cut off mid-word. */}
        <div className="relative flex h-[260px] shrink-0 flex-col items-center gap-[4px] overflow-hidden rounded-[24px] border-2 border-cream/18 pt-[44px] min-[900px]:h-full min-[900px]:w-[300px]">
          <span className="text-[16px] font-semibold text-cream/75">Typing</span>
          <span className="font-serif text-[48px] tracking-[-0.03em] text-cream">40 wpm</span>
          <span className="absolute top-[170px] left-[24px] w-[400px] text-[17px] text-cream/35 min-[900px]:top-[230px]">
            Hey, quick one about the pri|
          </span>
        </div>

        {/* Talking: the words keep coming. */}
        <div className="relative flex h-[400px] shrink-0 flex-col items-center gap-[4px] overflow-hidden rounded-[24px] pt-[44px] min-[900px]:h-full min-[900px]:flex-1">
          <div
            className="absolute -inset-[30px]"
            style={{
              backgroundImage: 'url(/landing/talking.jpg)',
              backgroundSize: 'cover',
              backgroundPosition: 'center 30%',
              filter: 'blur(6px) saturate(1.1)',
            }}
          />
          <div className="absolute inset-0 bg-[linear-gradient(180deg,rgba(0,0,0,0.25),rgba(0,0,0,0.05)_40%,rgba(0,0,0,0.25))]" />
          <span className="relative text-[16px] font-semibold text-white/90">Talking</span>
          <span className="relative font-serif text-[48px] tracking-[-0.03em] text-white">150 wpm</span>
          <Svg
            html={TALK_STREAM}
            viewBox="0 0 880 200"
            width={880}
            height={200}
            className="absolute top-[180px] left-1/2 max-w-none -translate-x-1/2"
          />
          <div className="absolute top-[310px] left-1/2 min-[900px]:top-[340px] flex h-[44px] -translate-x-1/2 items-center gap-[10px] rounded-full border border-white/10 bg-[rgba(24,25,28,0.95)] px-[14px]">
            <Bars heights={[8, 18, 26, 14, 22, 10, 16, 6]} />
          </div>
        </div>
      </div>
    </section>
  )
}
