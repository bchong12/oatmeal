# Oatmeal

Meeting notes and dictation for the Mac. Everything is transcribed on your Mac, and the notes are
written by the AI you already pay for.

- **Oatmeal Notes** records your mic and the other side of the call (Zoom, Meet, Teams, FaceTime),
  with no bot joining. When the meeting ends, Claude Code, Codex or Gemini CLI writes Granola-style
  notes from the transcript, on your own plan.
- **Oatmeal Flow** works in any app: hold right ⌥, talk, let go, and the words are typed where your
  cursor is. It drops the ums, follows "scratch that", and handles spoken punctuation.

## How notes get written

Oatmeal runs a small MCP server on your Mac (`http://127.0.0.1:29985/mcp`). When a meeting is saved,
it starts whichever CLI you picked in Settings and gives it just two tools: read the meeting, and save
its notes. Nothing goes to an Oatmeal server.

| Writer | Runs | Uses |
|---|---|---|
| Claude Code | `claude -p` | your Claude plan |
| Codex | `codex exec` | your ChatGPT plan |
| Gemini CLI | `gemini -p` | your Google account |

Claude Code and Codex have been tested end to end. Gemini CLI support is built in but hasn't been
tested end to end yet.

Any other MCP client (Claude, ChatGPT, Cursor and so on) can use the same server to read and search
your meetings. The tools are `list_meetings`, `get_meeting`, `update_meeting` and `search_dictations`.

## Features

- On-device speech to text: Parakeet (default), Whisper, Qwen3-ASR or Apple Speech
- Meeting detection, with titles from Apple Calendar
- Finder-style folders: nest them, drag meetings and folders between them, multi-select to move,
  merge or delete
- Search across titles, notes and transcripts
- Dictation dictionary, snippets and per-app style

## Build it

You need macOS 14 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd app
xcodegen generate
open Oatmeal.xcodeproj
```

Then run the `Oatmeal` scheme. Tests: `xcodebuild -project Oatmeal.xcodeproj -scheme Oatmeal test`.

### Signing

Out of the box the app is signed ad-hoc, so anyone can build it. Ad-hoc signatures change with every
build, so macOS asks for the microphone and Accessibility again after each rebuild. To keep those
permissions, sign with your own certificate: copy `app/Config/Signing.local.example.xcconfig` to
`app/Config/Signing.local.xcconfig` and fill it in. Git ignores that file.

## Layout

```
app/
  Sources/
    App/        app entry, app state, logging
    Design/     colours, type, and Oatmeal's own controls (buttons, menus, dialogs, switches)
    MCP/        the local MCP server, its tools, and the Claude Code / Codex / Gemini note writers
    Pill/       the floating pill and the right ⌥ key
    Voice/      recording, system audio, speech models, dictation and text clean-up
    Views/      Notes, Flow and Settings
  Tests/
  project.yml   XcodeGen project
```

## License

MIT, see [LICENSE](LICENSE). Young Serif and Figtree are under the SIL Open Font License
(`app/Resources/Fonts/OFL.txt`). Claude, ChatGPT, Gemini and the calendar logos belong to their
owners and are only used to show which service a setting refers to.
