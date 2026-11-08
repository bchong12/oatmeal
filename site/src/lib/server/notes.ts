// Oatmeal AI: writes a meeting's notes with Claude, for Pro members who don't have Claude Code, Codex
// or Gemini CLI on their Mac. Uses the site owner's ANTHROPIC_API_KEY. The same Granola-style notes
// the Mac app asks those CLIs for.

import Anthropic from '@anthropic-ai/sdk'
import { env } from '../env'

export interface MeetingInput {
  title: string
  startedAt: string
  attendees: string[]
  /** "Speaker: text" lines, in order. */
  transcript: string
  /** What the user typed during the meeting. */
  myNotes: string
}

export interface WrittenNotes {
  title: string
  notes: string
  summary: string[]
}

const SYSTEM = `You write meeting notes in the style of Granola: short topic headings with terse bullets.

Read the whole transcript and the user's own notes. Speaker "You" is the user; "Them" is everyone else on the call. The transcript is machine-made, so silently correct mis-heard words, names and jargon from context. Never add anything that wasn't said.

Return JSON with:
- title: short and specific, 2 to 6 words, from what was discussed.
- notes: 2 to 6 topic sections in meeting order, each "### Short topic" followed by 2 to 6 terse "- " bullets. Fragments, not sentences. Keep names, numbers, dates, prices and decisions exact. Build the sections around what the user wrote in their own notes. End with a "### Next steps" section, one clear task per bullet starting with a verb, with an owner and date only if they were said; leave it out if nothing was agreed.
- summary: 1 to 3 short lines with the gist.`

const SCHEMA = {
  type: 'object',
  properties: {
    title: { type: 'string' },
    notes: { type: 'string' },
    summary: { type: 'array', items: { type: 'string' } },
  },
  required: ['title', 'notes', 'summary'],
  additionalProperties: false,
} as const

export class NotesError extends Error {}

export async function writeNotes(meeting: MeetingInput): Promise<WrittenNotes> {
  if (!env.anthropicKey) throw new NotesError('Oatmeal AI is not set up on this site.')
  if (!meeting.transcript.trim()) throw new NotesError('This meeting has no transcript to write notes from.')
  const client = new Anthropic({ apiKey: env.anthropicKey })
  const header = [`Meeting: ${meeting.title || 'Untitled'}`, `When: ${meeting.startedAt}`]
  if (meeting.attendees.length) header.push(`People: ${meeting.attendees.join(', ')}`)
  const content = `${header.join('\n')}\n\n<my_notes>\n${meeting.myNotes.trim() || '(none)'}\n</my_notes>\n\n<transcript>\n${meeting.transcript}\n</transcript>`

  const response = await client.beta.messages.create({
    model: 'claude-opus-5-5',
    max_tokens: 16000,
    system: SYSTEM,
    messages: [{ role: 'user', content }],
    output_config: { effort: 'medium', format: { type: 'json_schema', schema: SCHEMA } },
    // If a safety check declines the request, the API retries it on a fallback model in the same call.
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
  })
  if (response.stop_reason === 'refusal') throw new NotesError('Claude declined to write notes for this meeting.')
  if (response.stop_reason === 'max_tokens') throw new NotesError('The notes ran too long. Try again.')
  const text = response.content.flatMap((b) => (b.type === 'text' ? [b.text] : [])).join('')
  const parsed = JSON.parse(text) as WrittenNotes
  return { title: parsed.title.trim(), notes: parsed.notes.trim(), summary: parsed.summary.map((s) => s.trim()).filter(Boolean) }
}
