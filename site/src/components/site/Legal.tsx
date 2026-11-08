import { PageIntro } from './Page'
import { Shell } from './Shell'

// Starting points only. Have them reviewed for your own business and country.

export function LegalPage({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <Shell>
      <PageIntro eyebrow="Legal" title={title} />
      <article className="mx-auto flex max-w-[720px] flex-col gap-4 px-6 text-[16px] leading-[26px] text-ink/80 [&_h2]:mt-6 [&_h2]:font-serif [&_h2]:text-[26px] [&_h2]:text-ink [&_li]:ml-5 [&_li]:list-disc [&_ul]:flex [&_ul]:flex-col [&_ul]:gap-2">
        {children}
      </article>
    </Shell>
  )
}
