import { createFileRoute } from '@tanstack/react-router'
import { planFor } from '#/lib/plans'
import { appSession, json } from '#/lib/server/account'
import { NotesError, writeNotes, type MeetingInput } from '#/lib/server/notes'

const MAX_TRANSCRIPT = 400_000

// Oatmeal AI: the Mac app sends a meeting, Claude writes its notes. Pro and Business only.
export const Route = createFileRoute('/api/app/notes')({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const session = await appSession(request)
        if (!session) return json({ error: 'Sign in again.' }, 401)
        if ((await planFor(session.whopUserId)) === 'free') return json({ error: 'Oatmeal AI is part of Pro.' }, 402)

        const body = (await request.json().catch(() => null)) as Partial<MeetingInput> | null
        const meeting: MeetingInput = {
          title: String(body?.title ?? '').slice(0, 200),
          startedAt: String(body?.startedAt ?? ''),
          attendees: Array.isArray(body?.attendees) ? body.attendees.map(String).slice(0, 50) : [],
          transcript: String(body?.transcript ?? ''),
          myNotes: String(body?.myNotes ?? '').slice(0, 50_000),
        }
        if (meeting.transcript.length > MAX_TRANSCRIPT) return json({ error: 'This meeting is too long for Oatmeal AI.' }, 413)
        try {
          return json(await writeNotes(meeting))
        } catch (error) {
          if (error instanceof NotesError) return json({ error: error.message }, 422)
          console.error('[notes] failed:', error)
          return json({ error: 'Oatmeal AI could not write these notes. Try again.' }, 502)
        }
      },
    },
  },
})
