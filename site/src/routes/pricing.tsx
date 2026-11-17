import { createFileRoute, redirect } from '@tanstack/react-router'

// Oatmeal is free, so there's no pricing page. Old links land on the home page.
export const Route = createFileRoute('/pricing')({
  beforeLoad: () => {
    throw redirect({ to: '/', statusCode: 301 })
  },
})
