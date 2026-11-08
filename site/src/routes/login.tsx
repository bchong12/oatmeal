import { Link, createFileRoute } from '@tanstack/react-router'
import { ArrowRight } from 'lucide-react'
import { Card, PageIntro } from '#/components/site/Page'
import { Shell } from '#/components/site/Shell'

const ERRORS: Record<string, string> = {
  expired: 'That sign-in link expired. Try again.',
  denied: 'Sign-in was cancelled.',
  'not-ready': "Sign-in isn't switched on for this site yet. If it's yours, open /setup.",
}

export const Route = createFileRoute('/login')({
  validateSearch: (search: Record<string, unknown>): { error?: string } => ({ error: typeof search.error === 'string' ? search.error : undefined }),
  head: ({ match }) => ({ meta: [{ title: `Sign in · ${match.context.brand.name}` }] }),
  component: Login,
})

function Login() {
  const { error } = Route.useSearch()
  return (
    <Shell>
      <PageIntro eyebrow="Sign in" title="Welcome back.">
        <p className="text-[17px] text-muted">Use the account you bought your plan with. New here? Signing in is free.</p>
      </PageIntro>
      <div className="mx-auto max-w-[440px] px-6">
        <Card className="flex flex-col gap-4 p-6">
          {error && (
            <p role="alert" className="rounded-[10px] border border-live/30 bg-live/10 px-4 py-3 text-[14px] text-[#9b2d33]">
              {ERRORS[error] ?? 'Something went wrong. Try again.'}
            </p>
          )}
          <a href="/api/auth/whop" className="btn-honey py-3.5 text-[16px]">
            Continue to sign in
            <ArrowRight size={17} aria-hidden />
          </a>
          <p className="text-center text-[14px] text-muted">
            Just want the app?{' '}
            <Link to="/download" className="font-semibold text-ink underline underline-offset-4">
              Download it
            </Link>
          </p>
        </Card>
      </div>
    </Shell>
  )
}
