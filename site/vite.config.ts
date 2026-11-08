import { cloudflare } from '@cloudflare/vite-plugin'
import tailwindcss from '@tailwindcss/vite'
import { tanstackStart } from '@tanstack/react-start/plugin/vite'
import viteReact from '@vitejs/plugin-react'
import { whop } from '@whop/cli/vite'
import { defineConfig } from 'vite'

export default defineConfig({
  resolve: { tsconfigPaths: true },
  plugins: [
    cloudflare({ viteEnvironment: { name: 'ssr' } }),
    tailwindcss(),
    tanstackStart(),
    viteReact(),
    // Packs dist/ into the archive `whop apps deploy` uploads.
    whop({ disableTanstackDevtools: true }),
  ],
})
