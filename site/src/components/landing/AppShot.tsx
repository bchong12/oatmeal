// The hero's product demo: a light grey stage (the way notion.com shows its product) where each feature
// plays out for real. Flow: you talk and the cleaned-up words land in a team chat. Notes: a call ends and
// the notes write themselves in Oatmeal (the Notion-style app: white Record button, Meetings / Flow /
// Captures, a folder tree). Capture: you record a bug, and the polished version plays the way Screen
// Studio shows recordings (a soft frame, smooth zooms on the click, your camera in the corner), then
// waits on the shelf to paste into your agent. A tab bar under the stage switches demos and moves on
// by itself. Drawn in HTML (not video) so it stays sharp and never shows anyone's real data.

import { useEffect, useRef, useState } from 'react'
import { Face, Loop, Mark } from '#/components/site/Mark'
import { CLAUDE_BURST, SLACK } from './logos'
import { Svg } from './shared'

export type DemoTab = 'flow' | 'notes' | 'capture'
export type Tone = 'blue' | 'honey' | 'red'

export const DEMO_TABS: { id: DemoTab; label: string; sub: string; verb: string; tone: Tone; icon: string; ms: number }[] = [
  { id: 'flow', label: 'Flow', sub: 'Talk, and it’s typed', verb: 'types it', tone: 'blue', icon: 'M5 10v4M9 7v10M13 9v6M17 6v12M21 10v4', ms: 9000 },
  { id: 'notes', label: 'Notes', sub: 'Calls write themselves up', verb: 'writes it up', tone: 'honey', icon: 'M14 3H6v18h12V7zM14 3v4h4M9 12h6M9 16h4', ms: 10000 },
  { id: 'capture', label: 'Capture', sub: 'Your screen, face and voice', verb: 'records it', tone: 'red', icon: 'M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3', ms: 13000 },
]

const reduced = () => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches

/** Steps through a demo: returns how many of `times` (ms from mount) have passed. */
function usePhase(times: number[]) {
  const [p, setP] = useState(0)
  useEffect(() => {
    // Dev only: window.__oatPhase = n holds every demo at step n, to check each frame.
    const held = import.meta.env.DEV ? (window as unknown as { __oatPhase?: number }).__oatPhase : undefined
    if (held != null) return setP(held)
    if (reduced()) return setP(times.length)
    const ids = times.map((t, i) => window.setTimeout(() => setP(i + 1), t))
    return () => ids.forEach(clearTimeout)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  return p
}

function Icon({ d, className = 'h-[15px] w-[15px]' }: { d: string; className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={`shrink-0 ${className}`} fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={d} />
    </svg>
  )
}

const I = {
  panel: 'M3 5h18v14H3zM9 5v14',
  back: 'm15 18-6-6 6-6',
  chevron: 'm9 18 6-6-6-6',
  down: 'm6 9 6 6 6-6',
  doc: 'M14 3H6v18h12V7zM14 3v4h4',
  folder: 'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z',
  gear: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z',
  bell: 'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10.3 21a1.9 1.9 0 0 0 3.4 0',
  more: 'M5 12h.01M12 12h.01M19 12h.01',
  calendar: 'M4 5h16v16H4zM4 10h16M9 3v4M15 3v4',
  people: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8',
  sparkle: 'M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6',
  camera: 'M16 10l5-3v10l-5-3zM3 6h13v12H3z',
  mic: 'M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3ZM5 11a7 7 0 0 0 14 0M12 18v3',
  area: 'M4 8V5h3M17 5h3v3M20 16v3h-3M7 19H4v-3',
  window: 'M3 5h18v14H3zM3 9h18',
  screen: 'M3 4h18v12H3zM8 20h8M12 16v4',
  scissors: 'M6 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6ZM20 4 8.1 15.9M14.5 14.5 20 20M8.1 8.1 12 12',
  clipboard: 'M9 4h6v3H9zM8 5H6v16h12V5h-2',
  pause: 'M8 5v14M16 5v14',
  x: 'M18 6 6 18M6 6l12 12',
  check: 'm5 12 4.5 4.5L19 7',
  hash: 'M4 9h16M4 15h16M10 3 8 21M16 3l-2 18',
  send: 'm22 2-7 20-4-9-9-4ZM22 2 11 13',
  plus: 'M12 5v14M5 12h14',
  at: 'M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Zm0 0v1.5a2.5 2.5 0 0 0 5 0V12a9 9 0 1 0-3.5 7.1',
}

function Spinner({ className = 'h-[12px] w-[12px]' }: { className?: string }) {
  return <span className={`inline-block animate-spin rounded-full border-[1.6px] border-current border-r-transparent ${className}`} />
}

/** Fades and lifts a piece in once `on` turns true. */
function In({ on, delay = 0, className = '', children }: { on: boolean; delay?: number; className?: string; children: React.ReactNode }) {
  return (
    <div
      className={`transition-[opacity,transform] duration-500 ease-[cubic-bezier(0.2,0.7,0.2,1)] ${on ? 'translate-y-0 opacity-100' : 'translate-y-[6px] opacity-0'} ${className}`}
      style={{ transitionDelay: on ? `${delay}ms` : '0ms' }}
    >
      {children}
    </div>
  )
}

/** A Mac window on the stage: rounded at the top, running off the bottom edge like notion.com's shots. */
function Win({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return (
    <div
      className={`absolute inset-x-[14px] top-[14px] -bottom-px flex overflow-hidden rounded-t-[12px] border border-b-0 border-black/10 bg-white text-left text-ink shadow-[rgba(0,0,0,0.01)_0_0_2px,rgba(0,0,0,0.03)_0_4px_12px,rgba(0,0,0,0.05)_0_16px_40px] sm:inset-x-[36px] sm:top-[36px] ${className}`}
    >
      {children}
    </div>
  )
}

function Lights() {
  return (
    <div className="flex gap-[7px]">
      <span className="h-[11px] w-[11px] rounded-full bg-[#FF5F57]" />
      <span className="h-[11px] w-[11px] rounded-full bg-[#FEBC2E]" />
      <span className="h-[11px] w-[11px] rounded-full bg-[#28C840]" />
    </div>
  )
}

/** Oatmeal's pill, as PillView.swift draws it: a dark capsule (#18191C at 94%, a faint white edge, a soft
 *  shadow), 40 high, floating near the bottom of the screen over whatever app you're in. */
function PillShell({ show, children }: { show: boolean; children: React.ReactNode }) {
  return (
    <div
      className={`absolute bottom-[26px] left-1/2 z-20 flex h-[40px] -translate-x-1/2 items-center rounded-full border border-white/[0.08] bg-[rgba(24,25,28,0.94)] whitespace-nowrap text-white shadow-[0_6px_20px_rgba(0,0,0,0.28)] transition-[opacity,transform] duration-300 ease-out ${show ? 'translate-y-0 scale-100 opacity-100' : 'pointer-events-none translate-y-[8px] scale-90 opacity-0'}`}
    >
      {children}
    </div>
  )
}

/** The pill's rolling waveform: 24 thin bars, each new reading comes in on the left and slides right. */
function speechLevel(t: number) {
  // A phrase envelope over quick syllables, with a short breath every few seconds, like real speech.
  const phrase = 0.6 + 0.4 * Math.sin(t / 9)
  const syllable = 0.5 + 0.5 * Math.sin(t / 1.25 + Math.sin(t / 3.1) * 2)
  let l = phrase * (0.3 + 0.7 * syllable) * (0.8 + Math.random() * 0.35)
  if (t % 40 > 36) l *= 0.2
  return Math.pow(Math.min(1, l), 0.6)
}

function DotWaves({ on }: { on: boolean }) {
  const [levels, setLevels] = useState<number[]>(() => Array.from({ length: 24 }, (_, i) => speechLevel(24 - i)))
  useEffect(() => {
    if (!on || reduced()) return
    let t = 24
    const id = window.setInterval(() => {
      t += 1
      setLevels((v) => [speechLevel(t), ...v.slice(0, 23)])
    }, 60)
    return () => clearInterval(id)
  }, [on])
  return (
    <span className="flex h-[28px] w-[144px] items-center gap-[3px]">
      {levels.map((l, i) => (
        <span key={i} className="w-[3px] rounded-full bg-white transition-[height] duration-75" style={{ height: 3 + l * 23, opacity: 0.45 + 0.55 * l }} />
      ))}
    </span>
  )
}

/** Slack's app icon, as the pill shows the app the words are going into. */
function SlackIcon({ size = 22 }: { size?: number }) {
  return (
    <span className="flex shrink-0 items-center justify-center rounded-[6px] bg-white" style={{ width: size, height: size }}>
      <Svg html={SLACK} viewBox="0 0 24 24" className="h-[64%] w-[64%]" />
    </span>
  )
}

function PillButton({ children, red }: { children: React.ReactNode; red?: boolean }) {
  return <span className={`flex h-[28px] w-[28px] items-center justify-center rounded-full ${red ? 'bg-live' : 'bg-white/[0.12]'}`}>{children}</span>
}

// MARK: - Flow: talking into a team chat

function ChatMessage({ who, name, time, children, tint = '#FCEBC2' }: { who: 'g' | 'h' | 'k'; name: string; time: string; children: React.ReactNode; tint?: string }) {
  return (
    <div className="flex gap-[10px] py-[7px]">
      <span className="flex h-[34px] w-[34px] shrink-0 items-end justify-center overflow-hidden rounded-[8px]" style={{ background: tint }}>
        <Face who={who} className="h-[38px] w-[38px] translate-y-[3px]" />
      </span>
      <div className="flex min-w-0 flex-col">
        <span className="flex items-baseline gap-[8px]">
          <span className="text-[14px] font-semibold">{name}</span>
          <span className="text-[11px] text-black/40">{time}</span>
        </span>
        <span className="text-[14px] leading-[21px] text-black/85">{children}</span>
      </div>
    </div>
  )
}

const SAID = 'Checked it. Step 3 is wrong: the shortcut is right Option, not Command. Can you fix it before Friday?'

function FlowDemo() {
  // 0 the cursor waits in the box · 1 listening · 2 writing it down · 3 the words land · 4 sent
  const p = usePhase([700, 3700, 4600, 7000])
  const words = SAID.split(' ')
  const channel = (name: string, on?: boolean) => (
    <span key={name} className={`flex h-[28px] items-center gap-[7px] rounded-[6px] px-[8px] ${on ? 'bg-black/[0.06] font-semibold text-ink' : 'text-black/55'}`}>
      <Icon d={I.hash} className="h-[13px] w-[13px] text-black/40" />
      {name}
    </span>
  )
  return (
    <>
      <Win>
        <aside className="hidden w-[200px] shrink-0 flex-col gap-[2px] border-r border-black/[0.06] bg-[#F7F7F5] px-[10px] pt-[14px] text-[14px] md:flex">
          <div className="px-[6px] pb-[14px]">
            <Lights />
          </div>
          <div className="flex items-center gap-[8px] px-[8px] pb-[14px]">
            <Svg html={SLACK} viewBox="0 0 24 24" className="h-[16px] w-[16px]" />
            <span className="font-semibold">Acme</span>
          </div>
          <span className="px-[8px] pb-[4px] text-[12px] font-medium text-black/40">Channels</span>
          {channel('general')}
          {channel('launch', true)}
          {channel('design')}
          <span className="px-[8px] pt-[14px] pb-[4px] text-[12px] font-medium text-black/40">Messages</span>
          {['Maya Kim', 'Jordan Reyes'].map((n, i) => (
            <span key={n} className="flex h-[28px] items-center gap-[8px] px-[8px] text-black/55">
              <span className="flex h-[18px] w-[18px] items-end justify-center overflow-hidden rounded-[5px]" style={{ background: i ? '#D3E5EF' : '#DBEDDB' }}>
                <Face who={i ? 'k' : 'h'} className="h-[20px] w-[20px] translate-y-[2px]" />
              </span>
              {n}
            </span>
          ))}
        </aside>
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="flex h-[48px] shrink-0 items-center gap-[8px] border-b border-black/[0.06] px-[18px]">
            <span className="md:hidden">
              <Lights />
            </span>
            <Icon d={I.hash} className="h-[15px] w-[15px] text-black/45" />
            <span className="text-[15px] font-semibold">launch</span>
            <span className="ml-auto text-[12px] text-black/40">4 members</span>
          </div>
          <div className="flex min-h-0 flex-1 flex-col justify-end overflow-hidden px-[18px] pb-[10px]">
            <ChatMessage who="k" name="Jordan Reyes" time="11:02 AM" tint="#D3E5EF">
              Mac app build is up. Dictation feels way faster now 🎉
            </ChatMessage>
            <ChatMessage who="h" name="Maya Kim" time="11:05 AM" tint="#DBEDDB">
              Nice. I&rsquo;ll start on the launch post after lunch.
            </ChatMessage>
            <div className="my-[8px] flex items-center gap-[10px] text-[11px] font-medium text-black/40">
              <span className="h-px flex-1 bg-black/[0.07]" />
              New
              <span className="h-px flex-1 bg-black/[0.07]" />
            </div>
            <ChatMessage who="h" name="Maya Kim" time="2:14 PM" tint="#DBEDDB">
              Launch post is drafted. Can someone check the steps before it goes out?
            </ChatMessage>
            <ChatMessage who="k" name="Jordan Reyes" time="2:16 PM" tint="#D3E5EF">
              Steps 1 and 2 look right to me 👍
            </ChatMessage>
            <div className={`grid transition-[grid-template-rows] duration-500 ease-out ${p >= 4 ? 'grid-rows-[1fr]' : 'grid-rows-[0fr]'}`}>
              <div className="overflow-hidden">
                <ChatMessage who="g" name="You" time="2:18 PM">
                  {SAID}
                </ChatMessage>
              </div>
            </div>
          </div>
          {/* The message box: Flow types where your cursor is. */}
          <div className="shrink-0 px-[18px] pb-[132px]">
            <div className={`rounded-[10px] border px-[12px] pt-[10px] pb-[8px] transition-colors duration-300 ${p >= 1 && p < 4 ? 'border-black/30' : 'border-black/15'}`}>
              <div className="min-h-[42px] text-[14px] leading-[21px]">
                {p === 3 ? (
                  words.map((w, i) => (
                    <span key={i} className="animate-[oat-fade_0.18s_ease_both]" style={{ animationDelay: `${i * 75}ms` }}>
                      {w}{' '}
                    </span>
                  ))
                ) : (
                  <span className="text-black/35">Message #launch</span>
                )}
                {p < 3 && <span className="oat-blink ml-[1px] inline-block h-[17px] w-[1.5px] translate-y-[3px] bg-ink" />}
              </div>
              <div className="flex items-center gap-[10px] pt-[6px] text-black/35">
                <Icon d={I.plus} className="h-[15px] w-[15px]" />
                <Icon d={I.at} className="h-[15px] w-[15px]" />
                <span className={`ml-auto flex h-[26px] w-[30px] items-center justify-center rounded-[6px] transition-colors duration-300 ${p === 3 ? 'bg-[#007A5A] text-white' : 'text-black/30'}`}>
                  <Icon d={I.send} className="h-[13px] w-[13px]" />
                </span>
              </div>
            </div>
          </div>
        </div>
      </Win>

      {/* The real pill: listening (the app, the waves, Oatmeal's mark), writing it down, then what went in. */}
      <PillShell show={p === 1}>
        <span className="flex items-center gap-[10px] px-[12px]">
          <SlackIcon />
          <DotWaves on={p === 1} />
          <Loop width={17} color="rgba(255,255,255,0.5)" />
        </span>
      </PillShell>
      <PillShell show={p === 2}>
        <span className="flex items-center gap-[10px] px-[20px] text-[13px] font-semibold">
          <Spinner className="h-[13px] w-[13px] text-white/80" />
          Writing it down…
        </span>
      </PillShell>
    </>
  )
}

// MARK: - Notes: the call ends, the notes write themselves in Oatmeal

function Sidebar() {
  const item = (label: string, icon: string, on?: boolean, count?: number) => (
    <div key={label} className={`flex h-[28px] items-center gap-[9px] rounded-[6px] px-[8px] ${on ? 'bg-black/[0.05] font-medium text-ink' : 'text-[#5F5E5B]'}`}>
      <Icon d={icon} className={`h-[14px] w-[14px] ${on ? 'text-ink' : 'text-black/45'}`} />
      {label}
      {count ? <span className="ml-auto text-[12px] text-black/35">{count}</span> : null}
    </div>
  )
  const folder = (label: string, count: number, depth = 0, chevron = false) => (
    <div key={label} className="flex h-[28px] items-center gap-[6px] rounded-[6px] pr-[8px] text-[#5F5E5B]" style={{ paddingLeft: 4 + depth * 16 }}>
      <span className="flex w-[12px] justify-center text-black/35">{chevron && <Icon d={I.down} className="h-[10px] w-[10px]" />}</span>
      <Icon d={I.folder} className="h-[14px] w-[14px] text-[#E8B04A]" />
      {label}
      <span className="ml-auto text-[12px] text-black/35">{count}</span>
    </div>
  )
  return (
    <aside className="hidden w-[214px] shrink-0 flex-col border-r border-black/[0.06] bg-[#F7F7F5] px-[10px] pt-[14px] pb-[12px] text-[14px] md:flex">
      <div className="px-[6px] pb-[16px]">
        <Lights />
      </div>
      <div className="flex items-center gap-[8px] px-[8px] pb-[12px]">
        <Mark size={20} />
        <span className="font-semibold text-ink">Oatmeal</span>
      </div>
      <div className="mb-[12px] flex h-[30px] items-center gap-[9px] rounded-[7px] border border-black/10 bg-white px-[8px] text-[13px] font-medium text-ink shadow-[0_1px_1px_rgba(0,0,0,0.04)]">
        <span className="flex w-[14px] justify-center">
          <span className="h-[7px] w-[7px] rounded-full bg-live" />
        </span>
        Record a meeting
        <span className="ml-auto text-[12px] font-normal text-black/35">⌘N</span>
      </div>
      <div className="flex flex-col gap-[1px]">
        {item('Meetings', I.doc, true, 7)}
        {item('Flow', DEMO_TABS[0].icon)}
        {item('Captures', I.area)}
      </div>
      <div className="px-[8px] pt-[18px] pb-[4px] text-[12px] font-medium text-black/40">Folders</div>
      {folder('Clients', 4, 0, true)}
      {folder('Acme', 3, 1)}
      {folder('Team', 1)}
      <div className="mt-auto flex items-center justify-between px-[8px] text-[#5F5E5B]">
        <span className="flex items-center gap-[9px]">
          <Icon d={I.gear} className="h-[14px] w-[14px] text-black/45" />
          Settings
        </span>
        <Icon d={I.bell} className="h-[14px] w-[14px] text-black/45" />
      </div>
    </aside>
  )
}

function Property({ icon, name, children }: { icon: string; name: string; children: React.ReactNode }) {
  return (
    <div className="flex min-h-[30px] items-center text-[14px]">
      <span className="flex w-[118px] shrink-0 items-center gap-[8px] text-black/45">
        <Icon d={icon} className="h-[13px] w-[13px]" />
        {name}
      </span>
      <div className="flex min-w-0 flex-wrap items-center gap-[6px]">{children}</div>
    </div>
  )
}

function Person({ name, tint }: { name: string; tint: string }) {
  return (
    <span className="flex h-[22px] items-center gap-[6px] rounded-full bg-[#F1F1EF] pr-[8px] pl-[2px] text-[13px]">
      <span className="flex h-[18px] w-[18px] items-center justify-center rounded-full text-[8px] font-semibold text-[#37352F]" style={{ background: tint }}>
        {name
          .split(' ')
          .map((s) => s[0])
          .join('')}
      </span>
      {name}
    </span>
  )
}

function Todo({ done, children }: { done?: boolean; children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-[8px] text-[14px] leading-[22px]">
      <span className={`mt-[4px] flex h-[14px] w-[14px] shrink-0 items-center justify-center rounded-[3px] border-[1.4px] transition-colors duration-300 ${done ? 'border-ink bg-ink text-white' : 'border-ink/55'}`}>
        <Icon d={I.check} className={`h-[9px] w-[9px] transition-opacity duration-300 ${done ? 'opacity-100' : 'opacity-0'}`} />
      </span>
      <span className={`transition-colors duration-300 ${done ? 'text-black/35 line-through' : ''}`}>{children}</span>
    </div>
  )
}

function Bullet({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-[10px] text-[14px] leading-[22px]">
      <span className="mt-[9px] h-[5px] w-[5px] shrink-0 rounded-full bg-ink" />
      <span>{children}</span>
    </div>
  )
}

function NotesDemo() {
  // 0 the call is being recorded · 1 stopped, notes being written · 2 summary · 3 sections · 4 a to-do ticked
  const p = usePhase([1700, 3300, 4000, 8200])
  return (
    <>
      <Win>
        <Sidebar />
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="flex h-[42px] shrink-0 items-center gap-[10px] px-[14px] text-[13px] text-black/45">
            <span className="md:hidden">
              <Lights />
            </span>
            <Icon d={I.panel} className="h-[15px] w-[15px]" />
            <Icon d={I.back} className="h-[14px] w-[14px] text-black/25" />
            <span className="h-[14px] w-px bg-black/10" />
            <span className="truncate">
              Meetings <span className="text-black/30">›</span> Clients <span className="text-black/30">›</span> <span className="font-medium text-ink">Launch review with Maya</span>
            </span>
          </div>
          <div className="relative min-h-0 flex-1 overflow-hidden">
            <div className="mx-auto w-full max-w-[700px] px-[22px] pt-[18px] sm:px-[44px] sm:pt-[26px]">
              <span className="flex h-[46px] w-[46px] items-center justify-center rounded-[10px] bg-[#F1F1EF] text-black/40">
                <Icon d={I.doc} className="h-[22px] w-[22px]" />
              </span>
              <div className="flex items-start justify-between gap-[12px] pt-[12px]">
                <h3 className="text-[30px] leading-[36px] font-bold tracking-[-0.03em]">Launch review with Maya</h3>
                <Icon d={I.more} className="mt-[10px] h-[16px] w-[16px] text-black/35" />
              </div>
              <div className="flex flex-col pt-[10px]">
                <Property icon={I.calendar} name="When">
                  <span>Monday, Nov 16 at 10:00 AM · 32 min</span>
                </Property>
                <Property icon={I.people} name="People">
                  <Person name="Maya Kim" tint="#DBEDDB" />
                  <Person name="Jordan Reyes" tint="#D3E5EF" />
                </Property>
                <Property icon={I.folder} name="Folder">
                  <span className="flex items-center gap-[5px] text-black/60">
                    <Icon d={I.folder} className="h-[13px] w-[13px] text-[#E8B04A]" />
                    Clients / Acme
                  </span>
                </Property>
              </div>
              <div className="mt-[14px] flex items-end justify-between border-b border-black/[0.08]">
                <div className="flex gap-[18px] text-[13px]">
                  <span className="border-b-2 border-ink pb-[7px] font-medium">Notes</span>
                  <span className="pb-[7px] text-black/45">My notes</span>
                  <span className="pb-[7px] text-black/45">Transcript</span>
                </div>
                <span className="flex items-center gap-[6px] pb-[7px] text-[12px] text-black/45">
                  {p >= 1 && p < 2 ? <Spinner className="h-[10px] w-[10px]" /> : <Icon d={I.sparkle} className="h-[12px] w-[12px]" />}
                  {p >= 1 && p < 2 ? 'Writing notes…' : p === 0 ? 'Write notes' : 'Redo notes'}
                </span>
              </div>

              <div className="relative pt-[16px]">
                <div
                  className={`absolute inset-x-0 top-[16px] flex items-center gap-[10px] rounded-[6px] bg-[#F7F7F5] px-[14px] py-[12px] text-[13px] text-black/55 transition-opacity duration-300 ${p === 0 || p === 1 ? 'opacity-100' : 'opacity-0'}`}
                >
                  {p === 0 ? (
                    <>
                      <span className="h-[8px] w-[8px] rounded-full bg-live" />
                      Recording. No bot joined; it hears your mic and the call on this Mac.
                    </>
                  ) : (
                    <>
                      <Spinner />
                      Claude Code is fixing the transcript and writing the notes.
                    </>
                  )}
                </div>
                <In on={p >= 2}>
                  <div className="flex gap-[10px] rounded-[6px] bg-[#F7F7F5] px-[14px] py-[12px] text-[14px] leading-[22px]">
                    <span>💡</span>
                    <span>Launch moves to Thursday. Onboarding gets one more pass first, and the download page goes live Wednesday.</span>
                  </div>
                </In>
                <div className="flex flex-col gap-[4px] pt-[16px]">
                  <In on={p >= 3}>
                    <h4 className="pb-[2px] text-[17px] font-semibold tracking-[-0.01em]">The plan</h4>
                  </In>
                  <In on={p >= 3} delay={120}>
                    <Bullet>Ship Thursday at 9 AM instead of Monday.</Bullet>
                  </In>
                  <In on={p >= 3} delay={240}>
                    <Bullet>Onboarding: cut the permissions screen down to one step.</Bullet>
                  </In>
                  <In on={p >= 3} delay={360}>
                    <Bullet>Maya wants the launch post out before the Friday sync.</Bullet>
                  </In>
                  <In on={p >= 3} delay={560}>
                    <h4 className="pt-[12px] pb-[2px] text-[17px] font-semibold tracking-[-0.01em]">Next steps</h4>
                  </In>
                  <In on={p >= 3} delay={680}>
                    <Todo done={p >= 4}>Send Maya the draft post</Todo>
                  </In>
                  <In on={p >= 3} delay={800}>
                    <Todo>
                      Maya: confirm the launch post went out, <span className="rounded-[4px] bg-[#FCEBC2] px-[4px]">Friday</span>
                    </Todo>
                  </In>
                  <In on={p >= 3} delay={920}>
                    <Todo>Jordan: update the download page and the FAQ</Todo>
                  </In>
                </div>
              </div>
            </div>
            <div className="pointer-events-none absolute inset-x-0 bottom-0 h-[72px] bg-gradient-to-t from-white to-white/0" />
          </div>
        </div>
      </Win>
      {/* The meeting pill while the call runs, as PillView draws it; "Save notes" hands it to your AI. */}
      <PillShell show={p === 0}>
        <span className="flex items-center gap-[12px] pr-[6px] pl-[14px] text-[13px] font-semibold">
          <span className="h-[9px] w-[9px] rounded-full bg-live" />
          <span className="tabular-nums">Recording · 31:58</span>
          <span className="hidden h-[28px] items-center rounded-full bg-white/[0.16] px-[10px] text-[12px] sm:flex">Meeting over? Save notes</span>
          <span className="flex items-center gap-[12px]">
            <PillButton>
              <Icon d="M4 6h16M4 12h10M4 18h14" className="h-[12px] w-[12px]" />
            </PillButton>
            <PillButton>
              <Icon d={I.pause} className="h-[11px] w-[11px]" />
            </PillButton>
            <PillButton red>
              <span className="h-[9px] w-[9px] rounded-[2px] bg-white" />
            </PillButton>
            <span className="flex h-[28px] w-[20px] items-center justify-center text-white/70">
              <Icon d="M5 12h14" className="h-[12px] w-[12px]" />
            </span>
          </span>
        </span>
      </PillShell>
    </>
  )
}

// MARK: - Capture: record a bug, watch it polished, paste it into your agent

/** The page being recorded: a bug in someone's own web app. `declined` shows the error after the click. */
function Billing({ declined, pressed }: { declined: boolean; pressed?: boolean }) {
  return (
    <div className="flex h-full flex-col bg-white text-[14px]">
      <div className="flex h-[34px] shrink-0 items-center gap-[10px] border-b border-black/[0.06] bg-[#F7F7F5] px-[12px]">
        <Lights />
        <span className="mx-auto w-[46%] truncate rounded-[6px] bg-white px-[10px] py-[2px] text-center text-[12px] text-black/45">app.acme.com/billing</span>
      </div>
      <div className="flex flex-1 flex-col gap-[14px] px-[28px] pt-[24px]">
        <span className="text-[22px] font-bold tracking-[-0.02em]">Billing</span>
        <div className="flex items-center justify-between border-t border-black/[0.06] pt-[12px] text-black/65">
          <span>Plan</span>
          <span className="font-medium text-ink">Team · $48 / month</span>
        </div>
        <div className="flex items-center justify-between border-t border-black/[0.06] pt-[12px] text-black/65">
          <span>Visa ending 4242</span>
          <span className={`rounded-[4px] px-[6px] text-[12px] font-semibold transition-colors duration-300 ${declined ? 'bg-[#FDE2DD] text-[#B4403A]' : 'bg-[#DBEDDB] text-[#1C3829]'}`}>
            {declined ? 'Card declined' : 'Active'}
          </span>
        </div>
        <span className={`mt-[4px] self-start rounded-[7px] bg-ink px-[14px] py-[7px] text-[13px] font-medium text-white transition-transform duration-150 ${pressed ? 'scale-95' : ''}`} data-click>
          Pay invoice
        </span>
        <div className={`flex items-center gap-[8px] self-start rounded-[8px] bg-[#FDE2DD] px-[12px] py-[8px] text-[13px] text-[#B4403A] transition-[opacity,transform] duration-300 ${declined ? 'opacity-100' : '-translate-y-[4px] opacity-0'}`}>
          <Icon d={I.x} className="h-[12px] w-[12px]" />
          Payment failed: your card was declined.
        </div>
        <span className="pt-[6px] text-[15px] font-semibold">Invoices</span>
        {[
          ['Nov 1, 2026', '$48.00', declined ? 'Failed' : 'Due'],
          ['Oct 1, 2026', '$48.00', 'Paid'],
        ].map(([d, amt, st]) => (
          <div key={d} className="-mt-[4px] flex items-center justify-between border-t border-black/[0.06] pt-[10px] text-[13px] text-black/60">
            <span>{d}</span>
            <span className="flex items-center gap-[14px]">
              {amt}
              <span className={`w-[44px] text-right font-medium ${st === 'Failed' ? 'text-[#B4403A]' : st === 'Due' ? 'text-black/45' : 'text-[#2E7D55]'}`}>{st}</span>
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}

/** A big Mac cursor, the way Screen Studio draws it. */
/** Screen Studio's camera: zoom in and bring the click to the middle, but stop at the page's edges so
 *  nothing outside it ever shows. */
function zoomOn(pt: { x: number; y: number; w: number; h: number }, scale = 1.85): React.CSSProperties {
  const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v))
  const tx = clamp(pt.w / 2 - scale * pt.x, pt.w - scale * pt.w, 0)
  const ty = clamp(pt.h / 2 - scale * pt.y, pt.h - scale * pt.h, 0)
  return {
    '--zx': `${tx}px`,
    '--zy': `${ty}px`,
    '--zs': scale,
    animation: 'oat-zoom 3.2s cubic-bezier(0.65,0,0.35,1) 0.5s both',
  } as React.CSSProperties
}

/** Where the click lands: the middle of the element marked data-click, in its container's own (unzoomed) px,
 *  measured in the browser so the cursor and the zoom sit on the button at any width. */
function useClickPoint() {
  const box = useRef<HTMLDivElement>(null)
  const [pt, setPt] = useState<{ x: number; y: number; w: number; h: number } | null>(null)
  useEffect(() => {
    const b = box.current
    if (!b) return
    const read = () => {
      const t = b.querySelector<HTMLElement>('[data-click]')
      if (!t) return
      const br = b.getBoundingClientRect()
      const tr = t.getBoundingClientRect()
      const s = br.width / (b.offsetWidth || 1)
      setPt({ x: (tr.left - br.left + tr.width / 2) / s, y: (tr.top - br.top + tr.height / 2) / s, w: b.offsetWidth, h: b.offsetHeight })
    }
    read()
    const ro = new ResizeObserver(read)
    ro.observe(b)
    return () => ro.disconnect()
  }, [])
  return [box, pt] as const
}

function Cursor({ x, y, click }: { x: number | string; y: number | string; click?: boolean }) {
  // The arrow's tip is 4.6, 2.8 px into its 22 px box, so a number puts the tip exactly on that point.
  const left = typeof x === 'number' ? x - 4.6 : x
  const top = typeof y === 'number' ? y - 2.8 : y
  return (
    <span className="pointer-events-none absolute z-10 transition-[left,top] duration-[900ms] ease-[cubic-bezier(0.45,0,0.2,1)]" style={{ left, top }}>
      <span className={`absolute -top-[14px] -left-[14px] h-[28px] w-[28px] rounded-full bg-[#2F80ED]/25 transition-[transform,opacity] duration-300 ${click ? 'scale-100 opacity-100' : 'scale-50 opacity-0'}`} />
      <svg viewBox="0 0 24 24" className="relative h-[22px] w-[22px] drop-shadow-[0_2px_3px_rgba(0,0,0,0.3)]" aria-hidden>
        <path d="M5 3l14 8-6.2 1.6L10 19z" fill="#111" stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
      </svg>
    </span>
  )
}

function StartBar({ pressed }: { pressed: boolean }) {
  const seg = (label: string, icon: string, on?: boolean) => (
    <span key={label} className={`flex h-[26px] items-center gap-[5px] rounded-[6px] px-[8px] ${on ? 'bg-white text-ink shadow-[0_1px_2px_rgba(0,0,0,0.08)]' : 'text-black/45'}`}>
      <Icon d={icon} className="h-[12px] w-[12px]" />
      {label}
    </span>
  )
  return (
    <div className="flex h-[46px] items-center gap-[8px] rounded-[12px] border border-black/10 bg-white px-[6px] text-[12px] font-medium whitespace-nowrap shadow-[0_14px_34px_rgba(0,0,0,0.16)]">
      <Icon d={I.x} className="mx-[4px] h-[12px] w-[12px] text-black/40" />
      <span className="flex items-center rounded-[8px] bg-[#F1F1EF] p-[2px]">
        {seg('Area', I.area)}
        {seg('Window', I.window, true)}
        <span className="hidden sm:contents">{seg('Screen', I.screen)}</span>
      </span>
      <span className="hidden items-center gap-[5px] px-[4px] text-black/70 lg:flex">
        <Icon d={I.camera} className="h-[13px] w-[13px]" />
        MacBook Pro Camera
      </span>
      <span className="hidden items-center gap-[5px] px-[4px] text-black/70 md:flex">
        <Icon d={I.mic} className="h-[13px] w-[13px]" />
        Microphone
      </span>
      <span className={`flex h-[34px] items-center gap-[7px] rounded-[9px] bg-ink px-[12px] text-white transition-transform duration-150 ${pressed ? 'scale-95' : ''}`}>
        <span className="h-[7px] w-[7px] rounded-full bg-live" />
        Record
        <span className="text-white/45">fn ⌘</span>
      </span>
    </div>
  )
}

function CameraBubble({ size = 72, className = '' }: { size?: number; className?: string }) {
  return (
    <span
      className={`flex items-end justify-center overflow-hidden border-[3px] border-white bg-white shadow-[0_10px_24px_rgba(0,0,0,0.2)] ${className}`}
      style={{ width: size, height: size, borderRadius: size * 0.24 }}
    >
      <Face className="h-[112%] w-[112%] max-w-none translate-y-[8%]" />
    </span>
  )
}

/** The shelf card, pared down: the polished take, its name and Paste. */
function Shelf({ pasted }: { pasted: boolean }) {
  return (
    <div className="w-[236px] overflow-hidden rounded-[12px] border border-black/[0.08] bg-white p-[6px] shadow-[0_16px_40px_rgba(0,0,0,0.14)]">
      <div className="relative aspect-[16/10] overflow-hidden rounded-[7px] bg-gradient-to-br from-[#F7F7F5] to-[#E4E3DF] p-[8px]">
        <div className="h-full overflow-hidden rounded-[4px] shadow-[0_3px_8px_rgba(0,0,0,0.08)]">
          <div className="h-[200%] w-[200%] origin-top-left scale-50">
            <Billing declined />
          </div>
        </div>
        <span className="absolute right-[6px] bottom-[6px] flex h-[24px] w-[24px] items-end justify-center overflow-hidden rounded-[6px] border-[1.5px] border-white bg-white shadow-[0_2px_6px_rgba(0,0,0,0.15)]">
          <Face className="h-[26px] w-[26px] max-w-none translate-y-[2px]" />
        </span>
        <span className="absolute top-[6px] right-[6px] rounded-[4px] bg-black/55 px-[4px] text-[10px] font-medium text-white tabular-nums">0:07</span>
      </div>
      <div className="flex items-center gap-[8px] px-[4px] pt-[7px] pb-[1px]">
        <span className="min-w-0 flex-1 truncate text-[13px] font-medium">Checkout bug</span>
        <span className={`flex h-[26px] shrink-0 items-center gap-[5px] rounded-[7px] px-[10px] text-[12px] font-medium text-white transition-colors duration-200 ${pasted ? 'bg-[#2E7D55]' : 'bg-ink'}`}>
          <Icon d={pasted ? I.check : I.clipboard} className="h-[11px] w-[11px]" />
          {pasted ? 'Pasted' : 'Paste'}
        </span>
      </div>
    </div>
  )
}

function CaptureDemo() {
  // 0 start bar · 1 recording (cursor heads for Pay) · 2 click, the card fails · 3 stop: the polished take
  // plays, zooming on the click · 4 it waits on the shelf · 5 pasted into Claude Code
  const p = usePhase([1900, 3400, 4400, 6400, 9600, 11300])
  const [secs, setSecs] = useState(0)
  useEffect(() => {
    if (p < 1 || p > 2) return
    const id = window.setInterval(() => setSecs((s) => s + 1), 1000)
    return () => clearInterval(id)
  }, [p])
  const recording = p >= 1 && p <= 2
  const [liveBox, livePt] = useClickPoint()
  const [zoomBox, zoomPt] = useClickPoint()
  const polished = p >= 3
  return (
    <>
      {/* Live: the browser window being recorded, with the area outlined, your face and the controls. */}
      <div className={`absolute inset-0 transition-[opacity,transform] duration-500 ease-[cubic-bezier(0.2,0.7,0.2,1)] ${polished ? 'pointer-events-none scale-[0.97] opacity-0' : 'opacity-100'}`}>
        <div className="absolute inset-x-[14px] top-[14px] bottom-[92px] sm:inset-x-[60px] sm:top-[32px]">
          <div ref={liveBox} className="relative h-full">
            <div className="h-full overflow-hidden rounded-[12px] border border-black/10 shadow-[0_16px_40px_rgba(0,0,0,0.1)]">
              <Billing declined={p >= 2} pressed={p === 2} />
            </div>
            <Cursor x={p >= 1 && livePt ? livePt.x : '62%'} y={p >= 1 && livePt ? livePt.y : '86%'} click={p === 2} />
            <CameraBubble size={84} className="absolute right-[18px] bottom-[18px]" />
          </div>
        </div>
        <div className="absolute bottom-[24px] left-1/2 -translate-x-1/2">
          <div className={`transition-[opacity,transform] duration-300 ${p === 0 ? 'opacity-100' : 'pointer-events-none translate-y-[10px] opacity-0'}`}>
            <StartBar pressed={false} />
          </div>
          {/* The recorder's controls, as RecorderPanels draws them: time and mic, Pause, Start over, camera, bin, Stop. */}
          <div
            className={`absolute bottom-0 left-1/2 flex -translate-x-1/2 items-center gap-[4px] rounded-[12px] border border-black/10 bg-white p-[6px] text-[13px] font-medium whitespace-nowrap shadow-[0_8px_24px_rgba(0,0,0,0.08)] transition-[opacity,transform] duration-300 ${recording ? 'opacity-100' : 'pointer-events-none translate-y-[10px] opacity-0'}`}
          >
            <span className="flex items-center gap-[8px] pr-[8px] pl-[8px]">
              <span className="h-[9px] w-[9px] rounded-full bg-live shadow-[0_0_0_4px_rgba(235,87,87,0.2)]" />
              <span className="w-[28px] tabular-nums">0:0{Math.min(secs, 9)}</span>
              <span className="flex h-[14px] items-end gap-[2px]">
                {[5, 9, 13, 8, 11].map((h, i) => (
                  <span key={i} className="w-[2.5px] rounded-[1.5px] bg-ink" style={{ height: h }} />
                ))}
              </span>
            </span>
            <span className="h-[22px] w-px bg-black/10" />
            <span className="hidden items-center gap-[6px] rounded-[6px] px-[8px] py-[5px] sm:flex">
              <Icon d={I.pause} className="h-[12px] w-[12px]" />
              Pause
            </span>
            <span className="hidden items-center gap-[6px] rounded-[6px] px-[8px] py-[5px] md:flex">
              <Icon d="M3 12a9 9 0 1 0 3-6.7L3 8M3 3v5h5" className="h-[12px] w-[12px]" />
              Start over
            </span>
            <span className="hidden px-[7px] text-black/60 md:block">
              <Icon d={I.camera} className="h-[14px] w-[14px]" />
            </span>
            <span className="hidden px-[7px] text-black/45 md:block">
              <Icon d="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14" className="h-[14px] w-[14px]" />
            </span>
            <span className="flex h-[34px] items-center gap-[8px] rounded-[8px] bg-ink px-[13px] text-white">
              <span className="h-[9px] w-[9px] rounded-[2px] bg-white" />
              Stop
              <span className="text-white/50">fn ⌘</span>
            </span>
          </div>
        </div>
      </div>

      {/* The polished take, Screen Studio style: a soft frame, a smooth zoom onto the click, your face. */}
      <div className={`absolute inset-0 flex items-center justify-center px-[14px] pb-[24px] transition-[opacity,transform] duration-500 ease-[cubic-bezier(0.2,0.7,0.2,1)] sm:px-[48px] ${polished ? 'opacity-100' : 'pointer-events-none scale-[1.03] opacity-0'}`}>
        <div className="flex w-full max-w-[920px] flex-col gap-[10px]">
          <div className="hidden items-center justify-between text-[12px] font-medium text-black/50 sm:flex">
            <span className="flex items-center gap-[6px]">
              <Icon d={I.sparkle} className="h-[12px] w-[12px]" />
              Polished in Oatmeal: zooms on your clicks, a clean frame, your camera
            </span>
          </div>
          <div className="relative aspect-[16/9.4] overflow-hidden rounded-[14px] bg-gradient-to-br from-[#F7F7F5] to-[#E4E3DF] p-[4.5%] shadow-[0_18px_44px_rgba(0,0,0,0.12)]">
            <div className="relative h-full overflow-hidden rounded-[10px] shadow-[0_10px_30px_rgba(0,0,0,0.14)]">
              {/* Zooms on the click itself: the point under the cursor stays put while everything grows around it. */}
              <div
                ref={zoomBox}
                key={polished ? 'zoom' : 'still'}
                className="relative h-full"
                style={{ transformOrigin: '0 0', ...(polished && zoomPt && !reduced() ? zoomOn(zoomPt) : {}) }}
              >
                <Billing declined pressed />
                {zoomPt && <Cursor x={zoomPt.x} y={zoomPt.y} />}
                {polished && zoomPt && (
                  <span
                    className="pointer-events-none absolute h-[30px] w-[30px] rounded-full bg-[#2F80ED]/30"
                    style={{ left: zoomPt.x - 15, top: zoomPt.y - 15, animation: 'oat-ripple 0.6s ease-out 0.25s both' }}
                  />
                )}
              </div>
            </div>
            <CameraBubble size={64} className="absolute right-[3%] bottom-[7%]" />
          </div>
        </div>
      </div>

      {/* Stopped: it waits on the shelf, raw and polished, ready to paste into your agent. */}
      <div className={`absolute right-[12px] bottom-[12px] z-20 flex origin-bottom-right scale-[0.74] flex-col items-end gap-[8px] transition-[opacity,transform] sm:scale-100 duration-500 ease-[cubic-bezier(0.2,0.7,0.2,1)] sm:right-[28px] sm:bottom-[24px] ${p >= 4 ? 'translate-y-0 opacity-100' : 'pointer-events-none translate-y-[16px] opacity-0'}`}>
        <Shelf pasted={p >= 5} />
      </div>
      {/* Pasted: Oatmeal's pill says where it went, centred at the bottom like every other pill. */}
      <PillShell show={p >= 5}>
        <span className="flex items-center gap-[10px] pr-[18px] pl-[10px] text-[13px] font-semibold">
          <span className="flex h-[22px] w-[22px] items-center justify-center rounded-[6px] bg-[#D97757]">
            <Svg html={CLAUDE_BURST} viewBox="0 0 24 24" className="h-[13px] w-[13px]" />
          </span>
          Pasted into Claude Code
        </span>
      </PillShell>
    </>
  )
}

// MARK: - Put together

function TabBar({ tab, onTab, playing }: { tab: DemoTab; onTab: (t: DemoTab) => void; playing: boolean }) {
  return (
    <div role="tablist" aria-label="See Oatmeal’s features" className="flex items-center gap-[28px]">
      {DEMO_TABS.map((t) => {
        const on = t.id === tab
        return (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={on}
            onClick={() => onTab(t.id)}
            className={`relative flex items-center gap-[7px] pb-[8px] text-[15px] font-medium transition-colors ${on ? 'text-ink' : 'text-black/40 hover:text-black/65'}`}
          >
            <Icon d={t.icon} className="h-[15px] w-[15px]" />
            {t.label}
            <span className="absolute inset-x-0 bottom-0 h-[2px] overflow-hidden rounded-full bg-black/[0.06]">
              {on && (
                <span
                  key={t.id}
                  className="block h-full origin-left rounded-full bg-ink"
                  style={playing ? { animation: `oat-progress ${t.ms}ms linear both` } : undefined}
                />
              )}
            </span>
          </button>
        )
      })}
    </div>
  )
}

export function HeroDemo({ tab, onTab, playing }: { tab: DemoTab; onTab: (t: DemoTab) => void; playing: boolean }) {
  return (
    <div className="flex flex-col items-center gap-[20px] sm:gap-[24px]">
      <div className="relative h-[560px] w-full overflow-hidden rounded-[16px] bg-[#F7F7F5] sm:h-[640px]">
        <div key={tab} className="absolute inset-0 animate-[oat-fade_0.4s_ease_both]">
          {tab === 'flow' ? <FlowDemo /> : tab === 'notes' ? <NotesDemo /> : <CaptureDemo />}
        </div>
      </div>
      <TabBar tab={tab} onTab={onTab} playing={playing} />
    </div>
  )
}
