<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { fetchJobs } from '@/api/admin'
import { getErrorMessage } from '@/api/client'
import type { PanelJob } from '@/types'

const jobs = ref<PanelJob[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

const columns = [
  { key: 'uuid', label: 'UUID' },
  { key: 'type', label: 'Typ' },
  { key: 'status', label: 'Status' },
  { key: 'progress', label: 'Fortschritt' },
  { key: 'server', label: 'Server' },
  { key: 'error', label: 'Fehler' },
  { key: 'created_at', label: 'Erstellt' },
]

onMounted(async () => {
  try {
    const response = await fetchJobs()
    jobs.value = response.data
  } catch (err) {
    jobs.value = []
    error.value = getErrorMessage(err, 'Jobs konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="space-y-4">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <DataTable :columns="columns" :rows="jobs" :loading="loading">
      <template #cell-status="{ row }">
        <StatusBadge :status="row.status" />
      </template>
      <template #cell-uuid="{ value }">
        <span class="font-mono text-xs">{{ value }}</span>
      </template>
      <template #cell-type="{ value }">
        <span class="font-mono text-xs">{{ value }}</span>
      </template>
      <template #cell-progress="{ value }">
        <span class="font-mono">{{ value != null ? `${value}%` : '—' }}</span>
      </template>
      <template #cell-server="{ row }">
        {{ row.server?.name ?? '—' }}
      </template>
      <template #cell-error="{ value }">
        <span class="text-xs text-panel-danger">{{ value ?? '—' }}</span>
      </template>
    </DataTable>
  </div>
</template>
