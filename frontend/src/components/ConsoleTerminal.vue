<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import '@xterm/xterm/css/xterm.css'
import { fetchConsoleHistory, sendConsoleCommand } from '@/api/servers'
import { createEcho } from '@/lib/echo'
import { useAuthStore } from '@/stores/auth'
import type Echo from 'laravel-echo'

const props = defineProps<{
  serverId: number
}>()

const terminalRef = ref<HTMLDivElement | null>(null)
let terminal: Terminal | null = null
let fitAddon: FitAddon | null = null
let echo: Echo<'reverb'> | null = null
let lineBuffer = ''
let pollTimer: number | null = null
let lastEventId = 0

function writeln(msg: string) {
  terminal?.writeln(msg)
}

async function loadHistory() {
  try {
    const data = await fetchConsoleHistory(props.serverId, 200)
    for (const event of data.events ?? []) {
      lastEventId = Math.max(lastEventId, Number(event.id) || 0)
      writeln(String(event.message ?? ''))
    }
  } catch {
    writeln('\x1b[90mHistory nicht verfügbar\x1b[0m')
  }
}

function subscribeEcho() {
  const auth = useAuthStore()
  if (!auth.token) return
  try {
    echo = createEcho(auth.token)
    echo
      .private(`servers.${props.serverId}`)
      .listen('.console.output', (payload: { id?: number; message?: string }) => {
        if (payload.id && payload.id <= lastEventId) return
        if (payload.id) lastEventId = payload.id
        writeln(String(payload.message ?? ''))
      })
    writeln('\x1b[32mLive-Stream verbunden (Reverb)\x1b[0m')
  } catch {
    writeln('\x1b[33mWebSocket nicht verfügbar — Polling-Fallback\x1b[0m')
    startPolling()
  }
}

function startPolling() {
  pollTimer = window.setInterval(async () => {
    try {
      const data = await fetchConsoleHistory(props.serverId, 50)
      for (const event of data.events ?? []) {
        const id = Number(event.id) || 0
        if (id <= lastEventId) continue
        lastEventId = id
        writeln(String(event.message ?? ''))
      }
    } catch {
      // ignore
    }
  }, 2000)
}

async function submitCommand(cmd: string) {
  if (!cmd.trim()) return
  try {
    await sendConsoleCommand(props.serverId, cmd)
  } catch (err) {
    writeln(`\x1b[31mBefehl fehlgeschlagen: ${String(err)}\x1b[0m`)
  }
}

function initTerminal() {
  if (!terminalRef.value) return

  terminal = new Terminal({
    theme: {
      background: '#0f1419',
      foreground: '#c8d0dc',
      cursor: '#e8a838',
      selectionBackground: '#e8a83833',
    },
    fontFamily: '"IBM Plex Mono", monospace',
    fontSize: 13,
    cursorBlink: true,
    scrollback: 5000,
  })

  fitAddon = new FitAddon()
  terminal.loadAddon(fitAddon)
  terminal.open(terminalRef.value)
  fitAddon.fit()

  terminal.writeln('\x1b[33m[GamePanel Console]\x1b[0m Server #' + props.serverId)
  terminal.write('$ ')

  terminal.onData((data) => {
    if (data === '\r') {
      terminal?.writeln('')
      const cmd = lineBuffer
      lineBuffer = ''
      void submitCommand(cmd)
      terminal?.write('$ ')
    } else if (data === '\u007F') {
      if (lineBuffer.length > 0) {
        lineBuffer = lineBuffer.slice(0, -1)
        terminal?.write('\b \b')
      }
    } else if (data >= ' ' || data === '\t') {
      lineBuffer += data
      terminal?.write(data)
    }
  })
}

function handleResize() {
  fitAddon?.fit()
}

onMounted(async () => {
  initTerminal()
  window.addEventListener('resize', handleResize)
  await loadHistory()
  subscribeEcho()
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', handleResize)
  if (pollTimer) window.clearInterval(pollTimer)
  echo?.leave(`servers.${props.serverId}`)
  echo?.disconnect()
  terminal?.dispose()
})
</script>

<template>
  <div class="border border-panel-border bg-panel-bg">
    <div class="flex items-center justify-between border-b border-panel-border px-4 py-2">
      <span class="text-xs uppercase tracking-wide text-panel-muted">Live Konsole</span>
      <span class="font-mono text-xs text-panel-accent">Server #{{ serverId }}</span>
    </div>
    <div ref="terminalRef" class="h-96 p-2" />
  </div>
</template>

<style scoped>
:deep(.xterm) {
  padding: 4px;
}
</style>
