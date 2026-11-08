import { defineConfig } from 'vitest/config'

// Tests cover the pure logic, so they skip the Cloudflare and TanStack plugins in vite.config.ts.
export default defineConfig({
  test: { include: ['src/**/*.test.ts'] },
})
