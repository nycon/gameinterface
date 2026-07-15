<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import { fetchAuditLogs } from '@/api/admin'
import { getErrorMessage } from '@/api/client'
import type { AuditLog } from '@/types'

const logs = ref<AuditLog[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

const columns = [
  { key: 'created_at', label: 'Zeit' },
  { key: 'user', label: 'Benutzer' },
  { key: 'action', label: 'Aktion' },
  { key: 'ip_address', label: 'IP' },
]

onMounted(async () => {
  try {
    const response = await fetchAuditLogs()
    logs.value = response.data
  } catch (err) {
    logs.value = []
    error.value = getErrorMessage(err, 'Audit-Logs konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="space-y-4">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <DataTable :columns="columns" :rows="logs" :loading="loading">
      <template #cell-action="{ value }">
        <span class="font-mono text-xs text-panel-accent">{{ value }}</span>
      </template>
      <template #cell-user="{ row }">
        {{ row.user?.name ?? '—' }}
      </template>
    </DataTable>
  </div>
</template>
