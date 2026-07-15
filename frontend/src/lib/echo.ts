import Echo from 'laravel-echo'
import Pusher from 'pusher-js'

declare global {
  interface Window {
    Pusher: typeof Pusher
    Echo?: Echo<'reverb'>
  }
}

window.Pusher = Pusher

export function createEcho(token: string): Echo<'reverb'> {
  const key = import.meta.env.VITE_REVERB_APP_KEY || 'gamepanel-key'
  const host = import.meta.env.VITE_REVERB_HOST || window.location.hostname
  const isHttps = window.location.protocol === 'https:'
  const port = Number(
    import.meta.env.VITE_REVERB_PORT || (isHttps ? window.location.port || 443 : window.location.port || 80),
  )
  const scheme = import.meta.env.VITE_REVERB_SCHEME || (isHttps ? 'https' : 'http')

  const echo = new Echo({
    broadcaster: 'reverb',
    key,
    wsHost: host,
    wsPort: port,
    wssPort: port,
    forceTLS: scheme === 'https',
    enabledTransports: ['ws', 'wss'],
    authEndpoint: '/broadcasting/auth',
    auth: {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
      },
    },
  })

  window.Echo = echo
  return echo
}
