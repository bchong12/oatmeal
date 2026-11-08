// Small helpers for server routes that redirect and set cookies.

export function redirect(location: string, cookies: string[] = []): Response {
  const headers = new Headers({ Location: location })
  for (const cookie of cookies) headers.append('Set-Cookie', cookie)
  return new Response(null, { status: 302, headers })
}

export function cookie(name: string, value: string, maxAgeSeconds: number): string {
  return `${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${maxAgeSeconds}`
}

export function readCookie(request: Request, name: string): string | undefined {
  for (const part of request.headers.get('cookie')?.split(';') ?? []) {
    const [key, ...rest] = part.trim().split('=')
    if (key === name) return decodeURIComponent(rest.join('='))
  }
  return undefined
}

/** The public URL of this deploy, from APP_URL or the request itself. */
export function baseUrl(request: Request, configured: string): string {
  return configured || new URL(request.url).origin
}
