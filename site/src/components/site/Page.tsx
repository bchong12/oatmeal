// The top of every inner page (pricing, download, account, setup, legal): eyebrow, serif heading,
// and whatever follows, centred under the nav.

export function PageIntro({
  eyebrow,
  title,
  highlight,
  children,
}: {
  eyebrow: string
  title: string
  /** Second line, set on a honey highlight like the landing page's "It's written." */
  highlight?: string
  children?: React.ReactNode
}) {
  return (
    <section className="mx-auto flex max-w-[760px] flex-col items-center gap-5 px-6 pt-24 pb-12 text-center sm:pt-32">
      <span className="text-[14px] text-black/55">{eyebrow}</span>
      <h1 className="font-serif text-[44px] leading-[1.04] tracking-[-0.045em] sm:text-[68px]">
        {title}
        {highlight && (
          <>
            <br />
            {/* Each wrapped line gets its own band, so the highlight still reads on a phone. */}
            <span className="box-decoration-clone rounded-[6px] bg-[linear-gradient(transparent_50%,var(--honey)_50%,var(--honey)_96%,transparent_96%)] px-1.5">
              {highlight}
            </span>
          </>
        )}
      </h1>
      {children}
    </section>
  )
}

export function Card({ children, className = '', honey = false }: { children: React.ReactNode; className?: string; honey?: boolean }) {
  return (
    <div
      className={`rounded-[12px] ${honey ? 'bg-white ring-1 ring-black/10 shadow-[rgba(0,0,0,0.027)_0_2px_7px,rgba(0,0,0,0.06)_0_12px_32px]' : 'bg-[#F9F9F8]'} ${className}`}
    >
      {children}
    </div>
  )
}
