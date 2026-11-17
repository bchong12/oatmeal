// "Works with the AI you already use", laid out like notion.com's "AI where your team works": two grey
// cards (a small label, one bold line, a round arrow) over white sheets of real product UI, with app
// logos floating at the edges and an ask bar on top. Left: Oatmeal's own "Who writes your notes"
// setting. Right: asking Claude about a meeting, answered through Oatmeal's MCP with the meeting cited.

import { Face, Mark } from '#/components/site/Mark'
import { Card, Sheet } from './Features'
import { Highlight } from './Hero'

const ASK_FROM = [
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

function Logo({ logo, size = 22 }: { logo: string; size?: number }) {
  return <img src={`/landing/${logo}.png`} alt="" className="shrink-0 rounded-[6px]" style={{ width: size, height: size }} />
}

/** An app icon floating at a sheet's edge, as notion.com floats Salesforce and Slack around its dashboard. */
function Float({ logo, className }: { logo: string; className: string }) {
  return (
    <span className={`oat-float absolute z-10 flex h-[44px] w-[44px] items-center justify-center rounded-[12px] bg-white shadow-[0_6px_18px_rgba(0,0,0,0.1)] ${className}`}>
      <Logo logo={logo} size={26} />
    </span>
  )
}

function Radio({ on }: { on?: boolean }) {
  return (
    <span className={`flex h-[16px] w-[16px] shrink-0 items-center justify-center rounded-full border-[1.5px] ${on ? 'border-ink' : 'border-[#D3D1CB]'}`}>
      {on && <span className="h-[8px] w-[8px] rounded-full bg-ink" />}
    </span>
  )
}

/** Oatmeal's Settings › General: who writes your notes. */
function WritersPicture() {
  const row = (logo: string, name: string, note: string, on?: boolean, good?: boolean) => (
    <div key={name} className="flex items-center gap-[12px] border-t border-[#EFEFED] py-[10px] first:border-t-0">
      <Logo logo={logo} size={30} />
      <div className="flex min-w-0 flex-1 flex-col">
        <span className="text-[14px] font-semibold">{name}</span>
        <span className={`truncate text-[12px] ${good ? 'text-[#2E7D55]' : 'text-black/45'}`}>{note}</span>
      </div>
      <Radio on={on} />
    </div>
  )
  return (
    <>
      <Sheet className="h-[86%] gap-[6px]">
        <span className="text-[12px] text-black/45">Settings · General</span>
        <span className="pb-[4px] text-[16px] font-semibold">Who writes your notes</span>
        <div className="flex flex-col">
          {row('claude', 'Claude Code', 'Found on this Mac · your Claude plan', true, true)}
          {row('openai', 'Codex', 'Found on this Mac · your ChatGPT plan', false, true)}
          {row('gemini', 'Gemini CLI', 'Not installed · npm i -g @google/gemini-cli')}
        </div>
        <div className="mt-[6px] flex items-center gap-[12px] border-t border-[#EFEFED] pt-[12px]">
          <div className="flex min-w-0 flex-1 flex-col">
            <span className="text-[14px] font-semibold">Write meeting notes automatically</span>
            <span className="truncate text-[12px] text-black/45">Your AI fixes the transcript and writes them up</span>
          </div>
          <span className="flex h-[20px] w-[34px] shrink-0 items-center justify-end rounded-full bg-ink p-[2px]">
            <span className="h-[16px] w-[16px] rounded-full bg-white" />
          </span>
        </div>
      </Sheet>
    </>
  )
}

/** Asking Claude about a meeting: it calls Oatmeal's MCP server and answers with the meeting cited. */
function AskPicture() {
  return (
    <>
      <Float logo="openai" className="top-[30px] left-[12px] [animation-delay:-0.4s]" />
      <Float logo="cursor" className="top-[70px] right-[12px] [animation-delay:-1s]" />
      <Float logo="raycast" className="bottom-[86px] left-[8px] [animation-delay:-0.2s]" />
      <Sheet className="h-[86%] max-w-[86%] gap-[10px]">
        <div className="flex items-center gap-[8px] text-[13px] font-semibold">
          <Logo logo="claude" size={20} />
          Claude
        </div>
        <span className="self-end rounded-[12px] bg-[#F1F1EF] px-[12px] py-[7px] text-[14px]">What did Maya and I decide about the launch?</span>
        <span className="flex items-center gap-[7px] self-start rounded-[8px] border border-black/[0.08] px-[9px] py-[5px] text-[12px] text-black/55">
          <Mark size={16} />
          Used Oatmeal · get_meeting
        </span>
        <span className="text-[14px] leading-[21px] text-black/85">
          You moved the launch to <b className="font-semibold text-ink">Thursday at 9 AM</b>. Onboarding gets one more pass first, and Maya sends the launch post before Friday.
        </span>
        <span className="flex items-center gap-[6px] self-start rounded-[6px] bg-[#F7F7F5] px-[8px] py-[4px] text-[12px] text-black/60">
          <span className="flex h-[14px] w-[14px] items-end justify-center overflow-hidden rounded-[3px] bg-[#FCEBC2]">
            <Face className="h-[16px] w-[16px] max-w-none translate-y-[2px]" />
          </span>
          Launch review with Maya · Nov 16
        </span>
      </Sheet>
      {/* The ask bar on top, as notion.com puts its question over the dashboard. */}
      <div className="absolute bottom-[16px] left-1/2 z-10 flex w-[min(88%,380px)] -translate-x-1/2 items-center gap-[10px] rounded-[12px] border border-black/[0.08] bg-white py-[8px] pr-[8px] pl-[14px] text-[14px] shadow-[0_8px_22px_rgba(0,0,0,0.1)]">
        <span className="flex-1 truncate text-black/45">What did Jordan say about the FAQ?</span>
        <span className="flex h-[26px] w-[26px] shrink-0 items-center justify-center rounded-full bg-[#D97757] text-white">
          <svg viewBox="0 0 24 24" className="h-[13px] w-[13px]" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
            <path d="M12 19V5M5 12l7-7 7 7" />
          </svg>
        </span>
      </div>
    </>
  )
}

export function YourAI() {
  return (
    <section id="your-ai" className="oat-enter mx-auto flex max-w-[1240px] scroll-mt-[100px] flex-col gap-[40px] px-5 pb-[64px] sm:gap-[48px] sm:pb-[96px]">
      <div className="flex flex-col items-center gap-[12px] text-center">
        <h2 className="font-serif text-[clamp(32px,4.4vw,48px)] leading-[1.1] tracking-[-0.035em] [text-wrap:balance]">
          Works with the <Highlight tone="blue">AI</Highlight> you already use.
        </h2>
        <p className="max-w-[600px] text-[18px] leading-[27px] text-black/70">Your notes are written by the AI you already pay for. Then any app that speaks MCP can ask about every meeting you&rsquo;ve had.</p>
      </div>
      <div className="grid gap-[24px] md:grid-cols-2">
        <Card id="writers" label="Your AI writes them" title="Notes written on the plan you already have." picture="aspect-[4/3] md:aspect-[16/12]">
          <WritersPicture />
        </Card>
        <Card id="ask" label="Ask your meetings" title="Ask any AI about any meeting." picture="aspect-[4/3] md:aspect-[16/12]">
          <AskPicture />
        </Card>
      </div>
      <div className="flex flex-col items-center gap-[14px]">
        <span className="text-[14px] text-black/50">Ask from any app that speaks MCP</span>
        <div className="flex flex-wrap items-center justify-center gap-x-[22px] gap-y-[12px]">
          {ASK_FROM.map((a) => (
            <span key={a.name} className="flex items-center gap-[7px] text-[14px] font-medium text-black/60">
              <Logo logo={a.logo} size={20} />
              {a.name}
            </span>
          ))}
        </div>
      </div>
    </section>
  )
}
