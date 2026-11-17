// Questions people ask, Notion-style: a title on the left, plain rows with hairlines that open in place.

const QA: [string, React.ReactNode][] = [
  ['Is it really free?', 'Yes. There’s no paid plan. Transcription runs on your Mac and your notes are written by the AI you already have, so there’s nothing for Oatmeal to charge for. The code is open source under the MIT licence.'],
  ['Does a bot join my calls?', 'No. Oatmeal records your mic and the other side of the call on your Mac, in Zoom, Google Meet, Teams, FaceTime or a browser. Nothing joins the meeting.'],
  [
    'Where do my recordings go?',
    'They stay on your Mac. Speech is transcribed on your Mac, and recordings and screenshots are saved to your Pictures folder. When notes are written, your transcript goes to the AI you picked, the same way anything you send it does.',
  ],
  ['Which AI writes my notes?', 'Claude Code, Codex or Gemini CLI, whichever you have installed. It runs on your own plan and gets just two tools from Oatmeal: read a meeting, save its notes. You can switch in Settings.'],
  ['How does Flow work?', 'Hold right ⌥, talk, let go: the words are typed wherever your cursor is, in any app. It drops the ums, follows “scratch that”, and handles spoken punctuation. Double-tap right ⌥ to keep it listening hands-free.'],
  ['How do recordings get to my agent?', 'fn ⌘ records your screen with your camera and mic; fn Space takes a screenshot. Each one waits on a shelf, raw or polished, and Paste drops it into Claude Code, Cursor or any chat.'],
  ['What do I need?', 'A Mac on macOS 26 or later. For meeting notes, Claude Code, Codex or Gemini CLI installed on it.'],
]

export function Faq() {
  return (
    <section id="faq" className="oat-enter mx-auto grid max-w-[1240px] scroll-mt-[100px] gap-[28px] px-5 pb-[64px] sm:pb-[96px] lg:grid-cols-[320px_1fr] lg:gap-[64px]">
      <div className="flex flex-col gap-[10px]">
        <h2 className="font-serif text-[clamp(32px,4.4vw,48px)] leading-[1.1] tracking-[-0.035em]">Questions</h2>
        <p className="text-[16px] leading-[24px] text-black/60">The things people ask before they try it.</p>
      </div>
      <div className="flex flex-col border-t border-black/[0.08]">
        {QA.map(([q, a], i) => (
          <details key={q} className="group border-b border-black/[0.08]" open={i === 0}>
            <summary className="flex cursor-pointer list-none items-center justify-between gap-[16px] py-[18px] text-[17px] font-medium [&::-webkit-details-marker]:hidden">
              {q}
              <span className="flex h-[24px] w-[24px] shrink-0 items-center justify-center rounded-full text-black/45 transition-transform duration-200 group-open:rotate-45">
                <svg viewBox="0 0 24 24" className="h-[15px] w-[15px]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden>
                  <path d="M12 5v14M5 12h14" />
                </svg>
              </span>
            </summary>
            <p className="max-w-[720px] pb-[20px] text-[16px] leading-[25px] text-black/65">{a}</p>
          </details>
        ))}
      </div>
    </section>
  )
}
