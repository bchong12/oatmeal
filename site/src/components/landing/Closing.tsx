// Closing, as Notion ends its page: a soft grey band, one line and the buttons, with the cast peeking over
// its top edge.

import { Link } from '@tanstack/react-router'
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
          <Link to="/pricing" className="inline-flex min-h-[42px] items-center rounded-[8px] bg-white px-[18px] text-[16px] font-medium ring-1 ring-black/10 transition-colors hover:bg-[#F1F1EF]">
            See pricing
          </Link>
        </div>
      </div>
    </section>
  )
}
