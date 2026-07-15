<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import {
  fetchAdminDatabases,
  revealAdminDatabase,
  fetchNodeDbAccess,
} from '@/api/admin'
import { fetchNodes } from '@/api/nodes'
import { getErrorMessage } from '@/api/client'
import type { Node } from '@/types'

interface DbRow {
  id: number
  name: string
  username: string
  host: string
  port: number
  engine: string
  server?: {
    id: number
    name: string
    owner?: { id: number; name: string; email?: string }
    node?: { id: number; name: string; ip_address?: string; phpmyadmin_url?: string }
  }
}

const rows = ref<DbRow[]>([])
const nodes = ref<Node[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const revealed = ref<Record<number, string>>({})
const nodeCreds = ref<{
  phpmyadmin_url: string | null
  username: string
  password: string | null
  node_name: string
} | null>(null)

const columns = [
  { key: 'name', label: 'Datenbank' },
  { key: 'server', label: 'Server' },
  { key: 'owner', label: 'Kunde' },
  { key: 'node', label: 'Node' },
  { key: 'username', label: 'User' },
]

async function load() {
  loading.value = true
  error.value = null
  try {
    const [dbs, n] = await Promise.all([fetchAdminDatabases(), fetchNodes()])
    rows.value = dbs.data
    nodes.value = n.data
  } catch (err) {
    rows.value = []
    error.value = getErrorMessage(err, 'Datenbanken konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function reveal(id: number) {
  try {
    const res = await revealAdminDatabase(id)
    revealed.value = { ...revealed.value, [id]: res.password }
    if (res.phpmyadmin_url) {
      window.open(res.phpmyadmin_url, '_blank', 'noopener')
    }
  } catch (err) {
    error.value = getErrorMessage(err, 'Passwort konnte nicht gelesen werden')
  }
}

async function openNodeAdmin(nodeId: number) {
  try {
    const res = await fetchNodeDbAccess(nodeId)
    const node = nodes.value.find((n) => n.id === nodeId)
    nodeCreds.value = {
      phpmyadmin_url: res.phpmyadmin_url,
      username: res.username,
      password: res.password,
      node_name: node?.name ?? `Node #${nodeId}`,
    }
    if (res.phpmyadmin_url) {
      window.open(res.phpmyadmin_url, '_blank', 'noopener')
    }
  } catch (err) {
    error.value = getErrorMessage(err, 'Node-Zugang fehlgeschlagen')
  }
}

const onlineNodes = computed(() => nodes.value)

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <p class="text-sm text-panel-muted">
      Kunden-DBs liegen lokal auf dem jeweiligen Game-Node (MariaDB). phpMyAdmin läuft auf dem Node
      (HTTPS). Kunden sehen nur ihre eigene DB; mit dem Node-Admin-User siehst du alle.
    </p>

    <div class="flex flex-wrap gap-2">
      <button
        v-for="n in onlineNodes"
        :key="n.id"
        class="panel-btn-secondary text-sm"
        type="button"
        @click="openNodeAdmin(n.id)"
      >
        phpMyAdmin: {{ n.name }}
      </button>
    </div>

    <div
      v-if="nodeCreds"
      class="border border-panel-border bg-panel-surface p-4 text-sm space-y-1"
    >
      <div class="font-semibold">{{ nodeCreds.node_name }} — Admin-Login</div>
      <div>
        URL:
        <a
          v-if="nodeCreds.phpmyadmin_url"
          :href="nodeCreds.phpmyadmin_url"
          target="_blank"
          rel="noopener"
          class="text-panel-accent hover:underline font-mono text-xs"
        >{{ nodeCreds.phpmyadmin_url }}</a>
      </div>
      <div>User: <code class="font-mono">{{ nodeCreds.username }}</code></div>
      <div>
        Passwort:
        <code class="font-mono">{{ nodeCreds.password || '(nicht im Panel hinterlegt — Node neu installieren)' }}</code>
      </div>
    </div>

    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>

    <DataTable :columns="columns" :rows="rows" :loading="loading">
      <template #cell-server="{ row }">
        {{ row.server?.name ?? '—' }}
      </template>
      <template #cell-owner="{ row }">
        {{ row.server?.owner?.name ?? '—' }}
      </template>
      <template #cell-node="{ row }">
        {{ row.server?.node?.name ?? '—' }}
      </template>
      <template #actions="{ row }">
        <div class="inline-flex gap-1">
          <button class="panel-btn-secondary text-xs px-2 py-1" type="button" @click="reveal(row.id)">
            Passwort + PMA
          </button>
          <span v-if="revealed[row.id]" class="font-mono text-xs text-panel-accent self-center">
            {{ revealed[row.id] }}
          </span>
        </div>
      </template>
    </DataTable>
  </div>
</template>
