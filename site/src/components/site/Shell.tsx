// Every page's frame: the floating white nav at the top and the footer with the giant wordmark at the
// bottom. Built from the Purist "Oatmeal · landing (fun)" design (nav Ppt1qy, footer Puj1qy).

import { Link } from '@tanstack/react-router'
import { useBrand } from '#/lib/brand'
import { AppleLogo, Mark } from './Mark'

function Nav() {
  const brand = useBrand()
  return (
    <header className="sticky top-[20px] z-40 mx-auto mt-[20px] flex h-[60px] w-[calc(100%-32px)] max-w-[1000px] items-center justify-between rounded-[14px] border border-line bg-white/80 pr-[8px] pl-[14px] shadow-[0_1px_2px_rgba(28,25,21,0.04),0_8px_24px_-12px_rgba(28,25,21,0.18)] backdrop-blur-md sm:pl-[18px]">
      <Link to="/" className="flex min-w-0 items-center gap-[8px]">
        <Mark size={28} className="shrink-0" />
        <span className="truncate font-serif text-[22px] tracking-[-0.02em]">{brand.name.toLowerCase()}</span>
      </Link>
      <nav className="flex items-center gap-[20px] text-[14px] font-medium text-ink/70">
        <Link to="/" hash="flow" className="hidden transition-colors hover:text-ink md:block">
          Flow
        </Link>
        <Link to="/" hash="notes" className="hidden transition-colors hover:text-ink md:block">
          Notes
        </Link>
        <Link to="/" hash="your-ai" className="hidden transition-colors hover:text-ink sm:block">
          Your AI
        </Link>
        <Link to="/pricing" className="hidden transition-colors hover:text-ink sm:block">
          Pricing
        </Link>
        <Link
          to="/download"
          className="flex shrink-0 items-center gap-[8px] rounded-[8px] border-[1.5px] whitespace-nowrap border-ink bg-honey px-[14px] py-[9px] text-[14px] font-bold text-ink transition-transform hover:-translate-y-px sm:px-[16px] sm:py-[10px]"
        >
          <AppleLogo size={14} />
          Get it for Mac
        </Link>
      </nav>
    </header>
  )
}

function Footer() {
  const brand = useBrand()
  const link = 'text-[14px] font-semibold transition-colors hover:text-ink/60'
  return (
    <footer className="mx-auto flex max-w-[1240px] flex-col overflow-hidden px-5 pt-[48px]">
      <div className="flex flex-col gap-4 border-b-2 border-ink pb-[20px] sm:flex-row sm:items-center sm:justify-between">
        <nav className="flex flex-wrap gap-x-[26px] gap-y-2">
          <Link to="/" hash="flow" className={link}>
            Flow
          </Link>
          <Link to="/" hash="notes" className={link}>
            Notes
          </Link>
          <Link to="/pricing" className={link}>
            Pricing
          </Link>
          <Link to="/privacy" className={link}>
            Privacy
          </Link>
          <Link to="/terms" className={link}>
            Terms
          </Link>
          <Link to="/account" className={link}>
            Account
          </Link>
        </nav>
        <span className="text-[14px] text-ink/60">
          Made on a Mac, for a Mac. © {brand.companyName}
        </span>
      </div>
      {/* The giant wordmark: 230px in the design's 1200 column, shrinking with the screen. */}
      <div
        role="img"
        aria-label={brand.name}
        className="flex items-center justify-center gap-[0.12em] py-[0.15em] text-[min(230px,calc((100vw-40px)*0.2))]"
      >
        <Mark size={0} className="h-[1em] w-[1em] shrink-0" />
        <span className="font-serif text-[1em] leading-[1.13] tracking-[-0.05em] whitespace-nowrap">{brand.name.toLowerCase()}</span>
      </div>
    </footer>
  )
}

export function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-cream text-ink">
      <Nav />
      {/* Inner pages get room above the footer; the landing page ends on its own closing block. */}
      <main className="pb-24 has-[.oat-landing]:pb-0">{children}</main>
      <Footer />
    </div>
  )
}
