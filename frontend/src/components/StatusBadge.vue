<script setup lang="ts">
import { computed } from 'vue'
import type { StatusBadgeValue } from '@/types'

const props = defineProps<{
  status: StatusBadgeValue
}>()

const config = computed(() => {
  const map: Record<string, { color: string; label: string }> = {
    online: { color: 'bg-panel-success', label: 'Online' },
    offline: { color: 'bg-panel-muted', label: 'Offline' },
    installing: { color: 'bg-panel-warning animate-pulse', label: 'Installation' },
    starting: { color: 'bg-panel-warning animate-pulse', label: 'Startet' },
    stopping: { color: 'bg-panel-warning animate-pulse', label: 'Stoppt' },
    running: { color: 'bg-panel-success', label: 'Läuft' },
    stopped: { color: 'bg-panel-muted', label: 'Gestoppt' },
    maintenance: { color: 'bg-panel-warning', label: 'Wartung' },
    error: { color: 'bg-panel-danger', label: 'Fehler' },
    pending: { color: 'bg-panel-warning', label: 'Ausstehend' },
    completed: { color: 'bg-panel-success', label: 'Fertig' },
    failed: { color: 'bg-panel-danger', label: 'Fehlgeschlagen' },
  }
  return map[props.status] ?? { color: 'bg-panel-muted', label: String(props.status) }
})
</script>

<template>
  <span class="inline-flex items-center gap-1.5 text-xs">
    <span class="h-2 w-2 rounded-full" :class="config.color" />
    <span class="text-panel-text">{{ config.label }}</span>
  </span>
</template>
