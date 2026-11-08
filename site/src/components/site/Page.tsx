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
      <span className="text-[13px] font-semibold tracking-[1px] text-ink/60 uppercase">{eyebrow}</span>
      <h1 className="font-serif text-[44px] leading-[1.02] tracking-[-0.03em] sm:text-[68px]">
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
    <div className={`rounded-[18px] border-[1.5px] border-ink shadow-[4px_4px_0_var(--ink)] ${honey ? 'bg-honey' : 'bg-paper'} ${className}`}>{children}</div>
  )
}
