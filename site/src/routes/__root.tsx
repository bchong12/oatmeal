import { HeadContent, Link, Scripts, createRootRoute } from '@tanstack/react-router'
import { Shell } from '#/components/site/Shell'
import type { Brand } from '#/lib/brand'
import { getBrand } from '#/lib/server/fns'
import appCss from '../styles.css?url'

// The brand never changes while a page is open, so the browser asks for it once.
let browserBrand: Brand | undefined

export const Route = createRootRoute({
  beforeLoad: async () => {
    if (browserBrand) return { brand: browserBrand }
    const brand = await getBrand()
    if (typeof window !== 'undefined') browserBrand = brand
    return { brand }
  },
  head: ({ match }) => ({
    meta: [
      { charSet: 'utf-8' },
      { name: 'viewport', content: 'width=device-width, initial-scale=1' },
      { title: match.context.brand.name },
      { name: 'description', content: match.context.brand.tagline },
      { name: 'theme-color', content: '#FCF8EA' },
    ],
    links: [
      { rel: 'icon', href: '/favicon.svg', type: 'image/svg+xml' },
      { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
      { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossOrigin: 'anonymous' },
      { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Figtree:wght@400;500;600;700;800&family=Young+Serif&display=swap' },
      { rel: 'stylesheet', href: appCss },
    ],
  }),
  shellComponent: RootDocument,
  notFoundComponent: NotFound,
})

function NotFound() {
  return (
    <Shell>
      <section className="mx-auto flex max-w-[640px] flex-col items-center gap-5 px-6 pt-32 pb-20 text-center">
        <span className="text-[14px] font-semibold tracking-[1px] text-ink/60 uppercase">404</span>
        <h1 className="font-serif text-[56px] leading-[1] tracking-[-0.03em]">Nothing here.</h1>
        <p className="text-[18px] text-muted">That link doesn't go anywhere.</p>
        <Link to="/" className="btn-honey px-6 py-3 text-[16px]">
          Go home
        </Link>
      </section>
    </Shell>
  )
}

function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  )
}
