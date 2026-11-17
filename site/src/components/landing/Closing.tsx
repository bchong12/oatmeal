// Closing, as Notion ends its page: a soft grey band, one line and the buttons, with the cast peeking over
// its top edge.

import { useBrand } from '#/lib/brand'
import { Face } from '#/components/site/Mark'
import { MacCta } from './shared'

export function Closing() {
  const brand = useBrand()
  return (
    <section className="oat-enter mx-auto max-w-[1240px] px-5 pt-[60px]">
      <div className="relative flex flex-col items-center gap-[14px] rounded-[16px] bg-[#F6F5F4] px-[32px] py-[64px] text-center">
        <div className="absolute -top-[58px] left-1/2 flex -translate-x-1/2 items-end">
          <Face who="h" className="h-[78px] w-[78px] -rotate-[6deg]" />
          <Face className="-mx-[10px] h-[92px] w-[92px]" />
          <Face who="k" className="h-[78px] w-[78px] rotate-[6deg]" />
        </div>
        <h2 className="font-serif text-[clamp(32px,4.4vw,48px)] leading-[1.1] tracking-[-0.035em]">You talk. {brand.name} writes it down.</h2>
        <p className="max-w-[520px] text-[18px] leading-[27px] text-black/70">Flow for everything you'd type, Notes for every meeting, Capture for everything you'd rather show.</p>
        <div className="flex flex-wrap items-center justify-center gap-[12px] pt-[6px]">
          <MacCta label={`Get ${brand.name} free`} />
          <a
            href="https://github.com/bchong12/oatmeal"
            target="_blank"
            rel="noreferrer"
            className="inline-flex min-h-[42px] items-center gap-[8px] rounded-[8px] bg-white px-[18px] ring-1 ring-black/10 text-[16px] font-medium transition-colors hover:bg-[#F1F1EF]"
          >
            <svg viewBox="0 0 24 24" className="h-[16px] w-[16px]" aria-hidden><path fill="currentColor" d="M12 .5C5.7.5.5 5.7.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.3.8-.6v-2c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.3-1.7-1.3-1.7-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.6.2 2.8.1 3.1.8.8 1.2 1.8 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A11.5 11.5 0 0 0 23.5 12C23.5 5.7 18.3.5 12 .5Z" /></svg>
            Open source on GitHub
          </a>
        </div>
      </div>
    </section>
  )
}
