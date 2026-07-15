<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import DataTable from '@/components/DataTable.vue'
import {
  createBackup,
  deleteBackup,
  fetchBackups,
  restoreBackup,
} from '@/api/servers'
import { pollJob } from '@/api/jobs'
import { getErrorMessage } from '@/api/client'
import type { Backup } from '@/types'

const route = useRoute()
const serverId = computed(() => Number(route.params.id))

const backups = ref<Backup[]>([])
const loading = ref(true)
const busy = ref(false)
const error = ref<string | null>(null)
const info = ref<string | null>(null)

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'size', label: 'Größe' },
  { key: 'status', label: 'Status' },
  { key: 'created_at', label: 'Erstellt' },
]

function formatSize(bytes: number): string {
  if (bytes >= 1_073_741_824) return `${(bytes / 1_073_741_824).toFixed(1)} GB`
  if (bytes >= 1_048_576) return `${(bytes / 1_048_576).toFixed(1)} MB`
  return `${bytes} B`
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const response = await fetchBackups(serverId.value)
    backups.value = response.data
  } catch (err) {
    backups.value = []
    error.value = getErrorMessage(err, 'Backups konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function create() {
  busy.value = true
  error.value = null
  info.value = null
  try {
    const { job } = await createBackup(serverId.value)
    const done = await pollJob(job.uuid, { timeoutMs: 300_000 })
    if (done.status === 'failed') throw new Error(done.error || 'Backup fehlgeschlagen')
    info.value = 'Backup erstellt'
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Backup fehlgeschlagen')
  } finally {
    busy.value = false
  }
}

async function restore(row: Backup) {
  if (!confirm(`Backup „${row.name}“ wiederherstellen?`)) return
  busy.value = true
  error.value = null
  try {
    const { job } = await restoreBackup(serverId.value, row.id)
    const done = await pollJob(job.uuid, { timeoutMs: 300_000 })
    if (done.status === 'failed') throw new Error(done.error || 'Restore fehlgeschlagen')
    info.value = 'Restore abgeschlossen'
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Restore fehlgeschlagen')
  } finally {
    busy.value = false
  }
}

async function remove(row: Backup) {
  if (!confirm(`Backup „${row.name}“ löschen?`)) return
  busy.value = true
  try {
    await deleteBackup(serverId.value, row.id)
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Löschen fehlgeschlagen')
  } finally {
    busy.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <p class="text-sm text-panel-muted">Backups auf dem Game-Node</p>
      <button class="panel-btn-primary text-sm" :disabled="busy" @click="create">
        {{ busy ? 'Bitte warten…' : 'Backup erstellen' }}
      </button>
    </div>
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <p v-if="info" class="text-sm text-panel-success">{{ info }}</p>
    <DataTable :columns="columns" :rows="backups" :loading="loading">
      <template #cell-size="{ row }">
        <span class="font-mono">{{ formatSize(row.size_bytes) }}</span>
      </template>
      <template #cell-status="{ row }">
        <span class="text-xs">{{ row.status ?? '—' }}</span>
      </template>
      <template #actions="{ row }">
        <div class="flex gap-1">
          <button class="panel-btn-secondary text-xs px-2 py-1" :disabled="busy" @click="restore(row)">
            Restore
          </button>
          <button class="panel-btn-secondary text-xs px-2 py-1" :disabled="busy" @click="remove(row)">
            Löschen
          </button>
        </div>
      </template>
    </DataTable>
  </div>
</template>
