<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { createNode, fetchNodes } from '@/api/nodes'
import { getErrorMessage } from '@/api/client'
import type { Node } from '@/types'

const nodes = ref<Node[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const showForm = ref(false)
const creating = ref(false)
const createdToken = ref<string | null>(null)

const form = ref({
  name: '',
  hostname: '',
  ip_address: '',
})

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'hostname', label: 'Hostname' },
  { key: 'ip_address', label: 'IP' },
  { key: 'status', label: 'Status' },
  { key: 'servers_count', label: 'Server' },
  { key: 'last_heartbeat_at', label: 'Letzter Heartbeat' },
]

async function load() {
  loading.value = true
  error.value = null
  try {
    const response = await fetchNodes()
    nodes.value = response.data
  } catch (err) {
    nodes.value = []
    error.value = getErrorMessage(err, 'Nodes konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function submitCreate() {
  creating.value = true
  error.value = null
  createdToken.value = null
  try {
    const response = await createNode(form.value)
    createdToken.value = response.token
    showForm.value = false
    form.value = { name: '', hostname: '', ip_address: '' }
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Node konnte nicht erstellt werden')
  } finally {
    creating.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>

    <div
      v-if="createdToken"
      class="border border-panel-warning bg-panel-surface p-4 text-sm"
    >
      <p class="font-medium text-panel-warning">Node-Token (nur einmal sichtbar):</p>
      <code class="mt-2 block break-all font-mono text-xs">{{ createdToken }}</code>
      <button class="panel-btn-secondary mt-2 text-xs" @click="createdToken = null">Schließen</button>
    </div>

    <div class="flex justify-end">
      <button class="panel-btn-primary" @click="showForm = !showForm">
        {{ showForm ? 'Abbrechen' : 'Node hinzufügen' }}
      </button>
    </div>

    <form
      v-if="showForm"
      class="space-y-4 border border-panel-border bg-panel-surface p-4"
      @submit.prevent="submitCreate"
    >
      <div class="grid gap-4 sm:grid-cols-3">
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Name</label>
          <input v-model="form.name" required class="panel-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Hostname</label>
          <input v-model="form.hostname" required class="panel-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">IP-Adresse</label>
          <input v-model="form.ip_address" required type="text" class="panel-input" />
        </div>
      </div>
      <button type="submit" class="panel-btn-primary" :disabled="creating">
        {{ creating ? 'Erstelle…' : 'Node erstellen' }}
      </button>
    </form>

    <DataTable :columns="columns" :rows="nodes" :loading="loading">
      <template #cell-status="{ row }">
        <StatusBadge :status="row.status" />
      </template>
      <template #cell-last_heartbeat_at="{ value }">
        <span class="font-mono text-xs">{{ value ?? '—' }}</span>
      </template>
    </DataTable>
  </div>
</template>
