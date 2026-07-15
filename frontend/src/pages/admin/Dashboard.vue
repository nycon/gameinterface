<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { fetchDashboard } from '@/api/servers'
import { getErrorMessage } from '@/api/client'
import type { DashboardResponse } from '@/types'
import { serverNodeName, serverOwnerName } from '@/types'

const data = ref<DashboardResponse | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)

const serverColumns = [
  { key: 'name', label: 'Name' },
  { key: 'status', label: 'Status' },
  { key: 'owner', label: 'Kunde' },
  { key: 'node', label: 'Node' },
]

const jobColumns = [
  { key: 'type', label: 'Typ' },
  { key: 'status', label: 'Status' },
  { key: 'server', label: 'Server' },
  { key: 'created_at', label: 'Erstellt' },
]

onMounted(async () => {
  try {
    data.value = await fetchDashboard()
  } catch (err) {
    error.value = getErrorMessage(err, 'Dashboard konnte nicht geladen werden')
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="space-y-6">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>

    <div v-if="loading" class="text-sm text-panel-muted">Lade Dashboard…</div>

    <template v-else-if="data">
      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4 xl:grid-cols-7">
        <div class="panel-stat">
          <div class="panel-stat-label">Benutzer</div>
          <div class="panel-stat-value">{{ data.stats.users }}</div>
        </div>
        <div class="panel-stat">
          <div class="panel-stat-label">Nodes</div>
          <div class="panel-stat-value">{{ data.stats.nodes_online }}/{{ data.stats.nodes }}</div>
        </div>
        <div class="panel-stat">
          <div class="panel-stat-label">Server online</div>
          <div class="panel-stat-value">{{ data.stats.servers_online }}</div>
        </div>
        <div class="panel-stat">
          <div class="panel-stat-label">Server gesamt</div>
          <div class="panel-stat-value">{{ data.stats.servers }}</div>
        </div>
        <div class="panel-stat">
          <div class="panel-stat-label">Jobs pending</div>
          <div class="panel-stat-value text-panel-warning">{{ data.stats.jobs_pending }}</div>
        </div>
        <div class="panel-stat">
          <div class="panel-stat-label">Jobs running</div>
          <div class="panel-stat-value text-panel-accent">{{ data.stats.jobs_running }}</div>
        </div>
        <div class="panel-stat">
          <div class="panel-stat-label">Auslastung</div>
          <div class="panel-stat-value text-panel-accent">
            {{
              data.stats.servers
                ? Math.round((data.stats.servers_online / data.stats.servers) * 100)
                : 0
            }}%
          </div>
        </div>
      </div>

      <div class="grid gap-4 lg:grid-cols-2">
        <div>
          <h3 class="mb-2 text-sm font-medium text-panel-muted">Neueste Server</h3>
          <DataTable :columns="serverColumns" :rows="data.recent_servers" empty-text="Keine Server">
            <template #cell-status="{ row }">
              <StatusBadge :status="row.status" />
            </template>
            <template #cell-owner="{ row }">
              {{ serverOwnerName(row) }}
            </template>
            <template #cell-node="{ row }">
              {{ serverNodeName(row) }}
            </template>
          </DataTable>
        </div>
        <div>
          <h3 class="mb-2 text-sm font-medium text-panel-muted">Neueste Jobs</h3>
          <DataTable :columns="jobColumns" :rows="data.recent_jobs" empty-text="Keine Jobs">
            <template #cell-status="{ row }">
              <StatusBadge :status="row.status" />
            </template>
            <template #cell-server="{ row }">
              {{ row.server?.name ?? '—' }}
            </template>
            <template #cell-type="{ value }">
              <span class="font-mono text-xs">{{ value }}</span>
            </template>
          </DataTable>
        </div>
      </div>
    </template>
  </div>
</template>
