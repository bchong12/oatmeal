import { createFileRoute } from '@tanstack/react-router'
import { Shell } from '#/components/site/Shell'
import { Closing } from '#/components/landing/Closing'
import { Faster } from '#/components/landing/Faster'
import { Hero } from '#/components/landing/Hero'
import { Notes } from '#/components/landing/Notes'
import { Pricing } from '#/components/landing/Pricing'
import { LandingStyles } from '#/components/landing/shared'
import { YourAI } from '#/components/landing/YourAI'

// The landing page, built from the Purist design "Oatmeal · landing (fun)".
export const Route = createFileRoute('/')({
  component: Landing,
})

function Landing() {
  return (
    <Shell>
      <LandingStyles />
      <div className="oat-landing overflow-x-clip">
        <Hero />
        <Faster />
        <Notes />
        <YourAI />
        <Pricing />
        <Closing />
      </div>
    </Shell>
  )
}
