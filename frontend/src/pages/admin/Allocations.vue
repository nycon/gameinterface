<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import { fetchNodes } from '@/api/nodes'
import apiClient, { getErrorMessage } from '@/api/client'
import type { Node } from '@/types'

interface Allocation {
  id: number
  ip: string
  port: number
  protocol: string
  notes?: string | null
  server?: { id: number; name: string } | null
  node?: { id: number; name: string } | null
}

const allocations = ref<Allocation[]>([])
const nodes = ref<Node[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const creating = ref(false)
const showForm = ref(false)

const form = reactive({
  node_id: 0,
  ip: '',
  port_start: 25565,
  port_end: 25614,
  protocol: 'tcp' as 'tcp' | 'udp',
})

const columns = [
  { key: 'node', label: 'Node' },
  { key: 'ip', label: 'IP' },
  { key: 'port', label: 'Port' },
  { key: 'protocol', label: 'Proto' },
  { key: 'server', label: 'Server' },
  { key: 'notes', label: 'Notiz' },
]

async function load() {
  loading.value = true
  error.value = null
  try {
    const [a, n] = await Promise.all([
      apiClient.get('/admin/allocations', { params: { page: 1 } }),
      fetchNodes(),
    ])
    allocations.value = a.data.data ?? a.data
    nodes.value = n.data
    if (nodes.value[0] && !form.node_id) {
      form.node_id = nodes.value[0].id
      form.ip = nodes.value[0].ip_address
    }
  } catch (err) {
    allocations.value = []
    error.value = getErrorMessage(err, 'Allocations konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

function onNodeChange() {
  const node = nodes.value.find((n) => n.id === form.node_id)
  if (node) form.ip = node.ip_address
}

async function createRange() {
  creating.value = true
  error.value = null
  try {
    await apiClient.post('/admin/allocations', {
      node_id: form.node_id,
      ip: form.ip,
      port_start: form.port_start,
      port_end: form.port_end,
      protocol: form.protocol,
      notes: 'pool',
    })
    showForm.value = false
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Ports konnten nicht angelegt werden')
  } finally {
    creating.value = false
  }
}

async function remove(id: number) {
  if (!confirm('Allocation löschen?')) return
  try {
    await apiClient.delete(`/admin/allocations/${id}`)
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Löschen fehlgeschlagen')
  }
}

const freeCount = computed(() => allocations.value.filter((a) => !a.server).length)

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <p class="text-sm text-panel-muted">
        Freie Ports: {{ freeCount }} — beim Anlegen eines Nodes wird automatisch ein Pool (25565+)
        erstellt.
      </p>
      <button class="panel-btn-primary text-sm" type="button" @click="showForm = !showForm">
        {{ showForm ? 'Abbrechen' : 'Port-Range anlegen' }}
      </button>
    </div>

    <form
      v-if="showForm"
      class="grid gap-3 border border-panel-border bg-panel-surface p-4 md:grid-cols-2"
      @submit.prevent="createRange"
    >
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Node</label>
        <select v-model.number="form.node_id" class="panel-input" @change="onNodeChange">
          <option v-for="n in nodes" :key="n.id" :value="n.id">{{ n.name }}</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">IP</label>
        <input v-model="form.ip" required class="panel-input font-mono" />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Port von</label>
        <input v-model.number="form.port_start" type="number" min="1" max="65535" class="panel-input" />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Port bis</label>
        <input v-model.number="form.port_end" type="number" min="1" max="65535" class="panel-input" />
      </div>
      <p v-if="error" class="md:col-span-2 text-sm text-panel-danger">{{ error }}</p>
      <button class="panel-btn-primary md:col-span-2" type="submit" :disabled="creating">
        {{ creating ? 'Anlegen…' : 'Range anlegen' }}
      </button>
    </form>

    <p v-if="error && !showForm" class="text-sm text-panel-danger">{{ error }}</p>

    <DataTable :columns="columns" :rows="allocations" :loading="loading">
      <template #cell-node="{ row }">
        {{ row.node?.name ?? '—' }}
      </template>
      <template #cell-server="{ row }">
        {{ row.server?.name ?? 'frei' }}
      </template>
      <template #actions="{ row }">
        <button
          v-if="!row.server"
          class="panel-btn-secondary text-xs px-2 py-1 text-panel-danger"
          type="button"
          @click="remove(row.id)"
        >
          Löschen
        </button>
      </template>
    </DataTable>
  </div>
</template>
