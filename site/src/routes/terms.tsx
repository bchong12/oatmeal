import { createFileRoute } from '@tanstack/react-router'
import { LegalPage } from '#/components/site/Legal'
import { useBrand } from '#/lib/brand'

export const Route = createFileRoute('/terms')({
  head: ({ match }) => ({ meta: [{ title: `Terms · ${match.context.brand.name}` }] }),
  component: Terms,
})

function Terms() {
  const { name, companyName, supportEmail } = useBrand()
  return (
    <LegalPage title="Terms of service">
      <p>By using {name} you agree to these terms. {companyName} provides the app and service as is.</p>
      <h2>Recording people</h2>
      <p>
        You're responsible for telling people when you record a call and for following the recording laws where you and they are. Some places
        require everyone's consent.
      </p>
      <h2>Plans</h2>
      <p>Paid plans renew until you cancel, which you can do from your account any time. You keep the plan until the end of the period you paid for.</p>
      <h2>Contact</h2>
      <p>{supportEmail}</p>
    </LegalPage>
  )
}
