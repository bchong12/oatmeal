import { createFileRoute } from '@tanstack/react-router'
import { LegalPage } from '#/components/site/Legal'
import { useBrand } from '#/lib/brand'

export const Route = createFileRoute('/privacy')({
  head: ({ match }) => ({ meta: [{ title: `Privacy · ${match.context.brand.name}` }] }),
  component: Privacy,
})

function Privacy() {
  const { name, companyName, supportEmail } = useBrand()
  return (
    <LegalPage title="Privacy policy">
      <p>
        {name} is run by {companyName}. It's built so your meetings stay on your Mac. This page explains the little that leaves it.
      </p>
      <h2>On your Mac</h2>
      <ul>
        <li>Recordings, transcripts, meeting notes and dictations are stored on your Mac. We never receive them unless you use Oatmeal AI.</li>
        <li>Speech is transcribed on your Mac. Notes are written by the AI tool you choose (Claude Code, Codex or Gemini CLI), under that tool's own terms.</li>
      </ul>
      <h2>What we collect</h2>
      <ul>
        <li>When you sign in: your account id, name and email, to know which plan you have.</li>
        <li>When you buy a plan: payment is handled by our payment provider; we see that you have a plan, not your card.</li>
        <li>
          With Oatmeal AI (Pro): a meeting's title, attendees, transcript and your notes are sent to write its notes with Anthropic's Claude, and
          not kept by us afterwards.
        </li>
      </ul>
      <h2>Who we share it with</h2>
      <p>Our hosting and payment providers, and Anthropic for Oatmeal AI, each only as needed to run the service. We don't sell personal data.</p>
      <h2>Contact</h2>
      <p>{supportEmail}</p>
    </LegalPage>
  )
}
