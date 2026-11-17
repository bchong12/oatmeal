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
        <li>Recordings, transcripts, meeting notes and dictations are stored on your Mac. We never receive them.</li>
        <li>Speech is transcribed on your Mac. Notes are written by the AI tool you choose (Claude Code, Codex or Gemini CLI), under that tool's own terms.</li>
      </ul>
      <h2>What we collect</h2>
      <ul>
        <li>When you sign in: your account id, name and email. Oatmeal is free, so there's nothing to pay and no card to keep.</li>
      </ul>
      <h2>Who we share it with</h2>
      <p>Our hosting provider, only as needed to run the site. We don't sell personal data.</p>
      <h2>Contact</h2>
      <p>{supportEmail}</p>
    </LegalPage>
  )
}
