import { createFileRoute } from '@tanstack/react-router'
import { Shell } from '#/components/site/Shell'
import { Closing } from '#/components/landing/Closing'
import { Features } from '#/components/landing/Features'
import { Hero } from '#/components/landing/Hero'
import { Faq } from '#/components/landing/Faq'
import { WhyFree } from '#/components/landing/WhyFree'
import { LandingStyles } from '#/components/landing/shared'
import { YourAI } from '#/components/landing/YourAI'

// The landing page, Notion-style, from the Purist "Capture" frames and notion.com.
export const Route = createFileRoute('/')({
  component: Landing,
})

function Landing() {
  return (
    <Shell>
      <LandingStyles />
      <div className="oat-landing overflow-x-clip">
        <Hero />
        <Features />
        <YourAI />
        <WhyFree />
        <Faq />
        <Closing />
      </div>
    </Shell>
  )
}
