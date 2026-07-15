<script setup lang="ts">
import { onMounted } from 'vue'
import { RouterLink } from 'vue-router'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import ServerActions from '@/components/ServerActions.vue'
import { useServersStore } from '@/stores/servers'
import { serverGameName, serverMemoryDisplay, serverPort } from '@/types'

const store = useServersStore()

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'game', label: 'Spiel' },
  { key: 'status', label: 'Status' },
  { key: 'port', label: 'Port' },
  { key: 'memory', label: 'RAM' },
]

onMounted(() => {
  store.loadServers(false).catch(() => {})
})
</script>

<template>
  <div class="space-y-4">
    <p v-if="store.error" class="text-sm text-panel-danger">{{ store.error }}</p>
    <DataTable :columns="columns" :rows="store.servers" :loading="store.loading">
      <template #cell-name="{ row }">
        <RouterLink
          :to="`/client/servers/${row.id}/console`"
          class="font-medium text-panel-accent hover:underline"
        >
          {{ row.name }}
        </RouterLink>
      </template>
      <template #cell-game="{ row }">
        {{ serverGameName(row) }}
      </template>
      <template #cell-status="{ row }">
        <StatusBadge :status="row.status" />
      </template>
      <template #cell-port="{ row }">
        <span class="font-mono text-xs">{{ serverPort(row) }}</span>
      </template>
      <template #cell-memory="{ row }">
        <span class="font-mono text-xs">{{ serverMemoryDisplay(row) }}</span>
      </template>
      <template #actions="{ row }">
        <ServerActions :server="row" />
      </template>
    </DataTable>
  </div>
</template>
