// "Why it's free": three plain columns, Notion-style, on why Oatmeal costs nothing. Your Mac does the
// listening, the AI you already pay for does the writing, and the code is open.

import { Face } from '#/components/site/Mark'
import { Highlight } from './Hero'

function Column({ who, tint, title, children }: { who: 'g' | 'h' | 'k'; tint: string; title: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-[10px]">
      <span className="flex h-[52px] w-[52px] items-end justify-center overflow-hidden rounded-[12px]" style={{ background: tint }}>
        <Face who={who} className="h-[58px] w-[58px] translate-y-[5px]" />
      </span>
      <h3 className="pt-[6px] text-[20px] leading-[26px] font-semibold tracking-[-0.02em]">{title}</h3>
      <p className="text-[16px] leading-[25px] text-black/65">{children}</p>
    </div>
  )
}

export function WhyFree() {
  return (
    <section id="free" className="oat-enter mx-auto flex max-w-[1240px] scroll-mt-[100px] flex-col gap-[40px] px-5 pb-[64px] sm:gap-[56px] sm:pb-[96px]">
      <div className="flex flex-col items-center gap-[12px] text-center">
        <h2 className="font-serif text-[clamp(32px,4.4vw,48px)] leading-[1.1] tracking-[-0.035em] [text-wrap:balance]">
          Free. <Highlight tone="green">Really</Highlight> free.
        </h2>
        <p className="max-w-[580px] text-[18px] leading-[27px] text-black/70">No plans, no trial, no seat to pay for. Here&rsquo;s why it can be.</p>
      </div>
      <div className="grid gap-[36px] border-t border-black/[0.08] pt-[36px] md:grid-cols-3 md:gap-[48px]">
        <Column who="h" tint="#DDEBF1" title="Your Mac does the listening">
          Speech is turned into text on your Mac with Parakeet, so your voice and your calls are never sent anywhere to be transcribed. That&rsquo;s the expensive part other apps charge for.
        </Column>
        <Column who="g" tint="#FCEBC2" title="Your AI does the writing">
          Meeting notes are written by Claude Code, Codex or Gemini CLI, whichever you already have, on the plan you already pay for. Oatmeal hands it two tools: read a meeting, save its notes.
        </Column>
        <Column who="k" tint="#DBEDDB" title="The code is open">
          Oatmeal is open source under the MIT licence. Read how it works, build it yourself, or change it.{' '}
          <a href="https://github.com/bchong12/oatmeal" target="_blank" rel="noreferrer" className="font-medium text-ink underline decoration-black/20 underline-offset-[3px] hover:decoration-black/60">
            See it on GitHub
          </a>
          .
        </Column>
      </div>
    </section>
  )
}
