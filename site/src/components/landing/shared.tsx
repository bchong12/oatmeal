// What the landing sections share: the page's keyframes and layout rules, the desktop "stage" that keeps
// the design's absolute layout at 1440 and scales it to fit, the reveal-on-scroll hook, and small pieces.

import { Link } from '@tanstack/react-router'
import { useEffect, useRef, useState, type CSSProperties, type RefObject } from 'react'
import { AppleLogo } from '#/components/site/Mark'

/** The design is drawn at 1440 with absolute layers. At this width and up the page uses that layout. */
const DESKTOP = 1200

const CSS = `
.oat-landing { line-height: 1.35; letter-spacing: -0.005em; }

/* Desktop stage: the design's own absolute layout, scaled down to fit when the column is narrower. */
.oat-stage { width: 100%; }
@media (min-width: ${DESKTOP}px) {
  .oat-stage { container-type: inline-size; min-height: 0; max-width: calc(var(--sw) * 1px); aspect-ratio: var(--sw) / var(--sh); margin-inline: auto; }
  .oat-stage > .oat-stage-in {
    position: relative; width: calc(var(--sw) * 1px); height: calc(var(--sh) * 1px);
    transform-origin: 0 0; transform: scale(tan(atan2(100cqw, calc(var(--sw) * 1px))));
  }
  .oat-abs { position: absolute; left: var(--x); top: var(--y); margin: 0; }
  .oat-abs[style*="--w:"] { width: var(--w); }
  .oat-abs[style*="--h:"] { height: var(--h); }
  .oat-mobile { display: none !important; }
}
@media (max-width: ${DESKTOP - 0.02}px) {
  .oat-desktop { display: none !important; }
}

@keyframes oat-rise { from { opacity: 0; transform: translateY(24px); filter: blur(8px); } to { opacity: 1; transform: none; filter: blur(0); } }
@keyframes oat-wipe { from { clip-path: inset(0 100% 0 0); } to { clip-path: inset(0 0 0 0); } }
@keyframes oat-pop-in { from { opacity: 0; transform: scale(0.85); } to { opacity: 1; transform: scale(1); } }
@keyframes oat-slide { from { opacity: 0; transform: translateX(-16px); } to { opacity: 1; transform: none; } }
@keyframes oat-slide-8 { from { opacity: 0; transform: translateX(-8px); } to { opacity: 1; transform: none; } }
@keyframes oat-up-8 { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: none; } }
@keyframes oat-bar { from { transform: scaleY(0.35); } to { transform: scaleY(1); } }
@keyframes oat-float { from { transform: translateY(0); } to { transform: translateY(-4px); } }
@keyframes oat-blink { from { opacity: 1; } to { opacity: 0.3; } }
@keyframes oat-breathe { from { transform: scale(1); } to { transform: scale(1.04); } }
@keyframes oat-enter { from { opacity: 0; transform: translateY(48px); } to { opacity: 1; transform: none; } }

.oat-rise > * { animation: oat-rise 0.8s cubic-bezier(0.2, 0.7, 0.2, 1) both; }
.oat-rise > :nth-child(2) { animation-delay: 0.09s; }
.oat-rise > :nth-child(3) { animation-delay: 0.18s; }
.oat-rise > :nth-child(4) { animation-delay: 0.27s; }
.oat-rise > :nth-child(5) { animation-delay: 0.36s; }
.oat-wipe { animation: oat-wipe 0.6s cubic-bezier(0.2, 0.7, 0.2, 1) 0.7s both; }
.oat-slide { animation: oat-slide 0.6s cubic-bezier(0.2, 0.7, 0.2, 1) both; }
.oat-bars > * { animation: oat-bar 0.5s ease-in-out infinite alternate both; transform-origin: center; }
.oat-float { animation: oat-float 1.4s ease-in-out infinite alternate; }
.oat-blink { animation: oat-blink 0.8s ease-in-out infinite alternate; }
.oat-breathe { animation: oat-breathe 1.8s ease-in-out infinite alternate; }

/* Reveal once in view: children wait hidden until the list scrolls in. */
.oat-reveal > * { opacity: 0; }
.oat-reveal[data-in] > * { animation: var(--anim) both; }

/* Every section eases up as it scrolls in, tied to scroll like the design. */
@supports (animation-timeline: view()) {
  .oat-enter { animation: oat-enter linear both; animation-timeline: view(); animation-range: cover 0px cover 420px; }
}

@media (prefers-reduced-motion: reduce) {
  .oat-enter { animation: none !important; }
  .oat-bars > *, .oat-float, .oat-blink, .oat-breathe { animation: none !important; }
}
`

export function LandingStyles() {
  return <style dangerouslySetInnerHTML={{ __html: CSS }} />
}

/** Position a layer as the design does, from the desktop width up; below that it flows. */
export function at(x: number, y: number, w?: number, h?: number): CSSProperties {
  return {
    '--x': `${x}px`,
    '--y': `${y}px`,
    ...(w ? { '--w': `${w}px` } : {}),
    ...(h ? { '--h': `${h}px` } : {}),
  } as CSSProperties
}

/** The design's absolute layout at w×h, scaled to fit its column on desktop. Below desktop, children flow. */
export function Stage({
  w,
  h,
  className = '',
  innerClassName = '',
  innerStyle,
  children,
}: {
  w: number
  h: number
  className?: string
  innerClassName?: string
  innerStyle?: CSSProperties
  children: React.ReactNode
}) {
  return (
    <div className={`oat-stage ${className}`} style={{ '--sw': w, '--sh': h } as CSSProperties}>
      <div className={`oat-stage-in ${innerClassName}`} style={innerStyle}>{children}</div>
    </div>
  )
}

/** True once the element has scrolled into view (and stays true). */
export function useInViewOnce<T extends Element>(): [RefObject<T | null>, boolean] {
  const ref = useRef<T>(null)
  const [inView, setInView] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el || inView) return
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setInView(true)
          io.disconnect()
        }
      },
      { threshold: 0.01 },
    )
    io.observe(el)
    return () => io.disconnect()
  }, [inView])
  return [ref, inView]
}

/** SVG <animate> ignores CSS, so stop it by hand when the visitor asks for less motion. */
export function useSvgReducedMotion<T extends Element = HTMLElement>(): RefObject<T | null> {
  const ref = useRef<T>(null)
  useEffect(() => {
    const root = ref.current
    if (!root) return
    const media = matchMedia('(prefers-reduced-motion: reduce)')
    const apply = () => {
      root.querySelectorAll('svg').forEach((svg) => {
        if (media.matches) {
          svg.setCurrentTime(0)
          svg.pauseAnimations()
        } else svg.unpauseAnimations()
      })
    }
    apply()
    media.addEventListener('change', apply)
    return () => media.removeEventListener('change', apply)
  }, [])
  return ref
}

/** An inline SVG whose inner markup comes straight from the design. */
export function Svg({
  html,
  viewBox,
  className = '',
  width,
  height,
  style,
}: {
  html: string
  viewBox: string
  className?: string
  width?: number
  height?: number
  style?: CSSProperties
}) {
  return (
    <svg
      viewBox={viewBox}
      width={width}
      height={height}
      className={className}
      style={style}
      aria-hidden
      dangerouslySetInnerHTML={{ __html: html }}
    />
  )
}

/** The chunky honey "Get … for Mac" button. */
export function MacCta({ label }: { label: string }) {
  return (
    <Link to="/download" className="btn-honey px-[26px] py-[17px] text-[17px]">
      <AppleLogo size={17} />
      {label}
    </Link>
  )
}

/** The recording pill's waveform. Heights are the design's; the bars bounce out from the centre. */
export function Bars({ heights, colors, className = '' }: { heights: number[]; colors?: string[]; className?: string }) {
  const mid = (heights.length - 1) / 2
  return (
    <div className={`oat-bars flex h-[28px] items-center gap-[3px] ${className}`}>
      {heights.map((h, i) => (
        <div
          key={i}
          className="w-[3px] rounded-[2px]"
          style={{ height: h, background: colors?.[i] ?? '#fff', animationDelay: `${Math.abs(i - mid) * 0.07}s` }}
        />
      ))}
    </div>
  )
}

/** A section-level uppercase eyebrow. */
export function Eyebrow({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <span className={`text-[14px] font-semibold tracking-[1px] uppercase ${className}`}>{children}</span>
}
