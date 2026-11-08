// Closing: "You've got a lot to say. Oatmeal writes it down." over a blurred photo. Purist node Pu81qy.

import { useBrand } from '#/lib/brand'
import { MacCta } from './shared'

export function Closing() {
  const brand = useBrand()
  return (
    <section className="oat-enter mx-auto flex max-w-[1440px] px-3 pt-3 sm:px-[24px] sm:pt-[24px]">
      <div className="relative flex min-h-[560px] w-full flex-col items-center justify-center gap-[28px] overflow-hidden rounded-[24px] px-5 py-20 text-center sm:rounded-[32px] min-[1200px]:h-[720px]">
        <div
          className="absolute -inset-[40px]"
          style={{
            backgroundImage: 'url(/landing/closing.jpg)',
            backgroundSize: 'cover',
            backgroundPosition: 'center 40%',
            filter: 'blur(7px) saturate(1.15)',
          }}
        />
        <div className="absolute inset-0 bg-[rgba(28,20,14,0.38)]" />
        <h2 className="relative flex flex-col items-center font-serif font-normal tracking-[-0.035em] text-cream text-[clamp(42px,7.2vw,96px)] leading-[1.02]">
          <span>You've got a lot to say.</span>
          <span className="text-honey">{brand.name} writes it down.</span>
        </h2>
        <p className="relative max-w-[520px] text-[18px] leading-[26px] font-medium text-cream/90 sm:text-[20px] sm:leading-[28px]">
          Flow for everything you'd type. Notes for every meeting. Both in one free app.
        </p>
        <div className="relative">
          <MacCta label={`Get ${brand.name} for Mac`} />
        </div>
      </div>
    </section>
  )
}
