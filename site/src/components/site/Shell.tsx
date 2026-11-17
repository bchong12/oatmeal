// Every page's frame: the floating white nav at the top and the footer with the giant wordmark at the
// bottom. Notion-style: a plain white bar on top, a quiet footer with the giant wordmark.

import { Link } from '@tanstack/react-router'
import { useBrand } from '#/lib/brand'
import { AppleLogo, Mark } from './Mark'

function Nav() {
  const brand = useBrand()
  return (
    <header className="sticky top-0 z-40 mx-auto flex h-[64px] w-full max-w-[1240px] items-center justify-between bg-white/95 px-5 backdrop-blur-md">
      <Link to="/" className="flex min-w-0 items-center gap-[8px]">
        <Mark size={28} className="shrink-0" />
        <span className="truncate font-serif text-[19px] tracking-[-0.02em]">{brand.name}</span>
      </Link>
      <nav className="flex items-center gap-[20px] text-[15px] font-medium text-black/75">
        <Link to="/" hash="flow" className="hidden transition-colors hover:text-ink md:block">
          Flow
        </Link>
        <Link to="/" hash="notes" className="hidden transition-colors hover:text-ink md:block">
          Notes
        </Link>
        <Link to="/" hash="capture" className="hidden transition-colors hover:text-ink md:block">
          Capture
        </Link>
        <Link to="/" hash="your-ai" className="hidden transition-colors hover:text-ink sm:block">
          Your AI
        </Link>
        <Link to="/" hash="faq" className="hidden transition-colors hover:text-ink sm:block">
          FAQ
        </Link>
        <Link
          to="/download"
          className="btn-ink shrink-0 px-[14px] py-[8px] text-[14px] whitespace-nowrap"
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
  const link = 'text-[14px] font-medium text-black/70 transition-colors hover:text-ink'
  return (
    <footer className="mx-auto flex max-w-[1240px] flex-col overflow-hidden px-5 pt-[48px]">
      <div className="flex flex-col gap-4 border-b border-line pb-[20px] sm:flex-row sm:items-center sm:justify-between">
        <nav className="flex flex-wrap gap-x-[26px] gap-y-2">
          <Link to="/" hash="flow" className={link}>
            Flow
          </Link>
          <Link to="/" hash="notes" className={link}>
            Notes
          </Link>
          <Link to="/" hash="faq" className={link}>
            FAQ
          </Link>
          <a href="https://github.com/bchong12/oatmeal" target="_blank" rel="noreferrer" className={link}>
            GitHub
          </a>
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
        <span className="font-serif text-[1em] leading-[1.13] tracking-[-0.06em] whitespace-nowrap">{brand.name}</span>
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
