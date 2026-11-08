import { createFileRoute } from '@tanstack/react-router'
import { useEffect, useState } from 'react'
import { AppleLogo } from '#/components/site/Mark'
import { Card, PageIntro } from '#/components/site/Page'
import { Shell } from '#/components/site/Shell'
import { useBrand } from '#/lib/brand'
import { getDownload } from '#/lib/server/fns'

export const Route = createFileRoute('/download')({
  loader: async () => ({ download: await getDownload() }),
  head: ({ match }) => ({ meta: [{ title: `Download · ${match.context.brand.name}` }] }),
  component: Download,
})

function Download() {
  const { download } = Route.useLoaderData()
  const brand = useBrand()
  // Points the app at this site: Settings › Account then signs in here and checks the plan here.
  const [connect, setConnect] = useState('')
  useEffect(() => setConnect(`oatmeal://connect?${new URLSearchParams({ site: window.location.origin })}`), [])

  return (
    <Shell>
      <PageIntro eyebrow="Download" title={`${brand.name} for Mac`}>
        <p className="max-w-[520px] text-[18px] leading-[27px] text-muted">
          Free. Needs macOS 14 or later. Recording, transcription and dictation all run on your Mac.
        </p>
        {download.ready ? (
          <a href={download.url} className="btn-honey mt-2 px-7 py-4 text-[17px]">
            <AppleLogo size={17} />
            Download for Mac{download.version ? ` · ${download.version}` : ''}
          </a>
        ) : (
          <div className="mt-2 flex flex-col items-center gap-3">
            <span className="rounded-[10px] border-[1.5px] border-dashed border-ink/30 px-6 py-3.5 text-[16px] font-semibold text-ink/55">
              The Mac download is on its way
            </span>
            <a href={download.url} className="text-[15px] font-semibold underline underline-offset-4">
              Build it yourself from the open-source code
            </a>
          </div>
        )}
      </PageIntro>

      <section className="mx-auto grid max-w-[1000px] gap-5 px-6 md:grid-cols-3">
        <Step n={1} title="Open it">
          Drag {brand.name} to Applications and open it. Allow the microphone, and Accessibility so right ⌥ works in every app.
        </Step>
        <Step n={2} title="Connect your account">
          Back here, click below to link the app to your account, then sign in from Settings › Account.
          <a href={connect || undefined} className="btn-outline mt-4 w-full py-2.5 text-[14px]">
            Connect {brand.name}
          </a>
        </Step>
        <Step n={3} title="Talk">
          Hold right ⌥ and talk in any app. When a call starts, {brand.name} offers to take notes.
        </Step>
      </section>
    </Shell>
  )
}

function Step({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <Card className="flex flex-col gap-2 p-6">
      <span className="flex h-8 w-8 items-center justify-center rounded-full bg-honey font-bold">{n}</span>
      <h2 className="mt-2 font-serif text-[22px]">{title}</h2>
      <div className="flex flex-col text-[15px] leading-[23px] text-muted">{children}</div>
    </Card>
  )
}
