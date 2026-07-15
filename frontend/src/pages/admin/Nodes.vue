<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import { createNode, fetchNodes, regenerateNodeDeployToken } from '@/api/nodes'
import { getErrorMessage } from '@/api/client'
import type { Node } from '@/types'

const nodes = ref<Node[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const showForm = ref(false)
const creating = ref(false)
const regeneratingId = ref<number | null>(null)

const installBox = ref<{ command: string; token: string } | null>(null)
const copied = ref(false)

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
  try {
    const response = await createNode(form.value)
    installBox.value = {
      command: response.install_command,
      token: response.deploy_token,
    }
    showForm.value = false
    form.value = { name: '', hostname: '', ip_address: '' }
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Node konnte nicht erstellt werden')
  } finally {
    creating.value = false
  }
}

async function regenerate(id: number) {
  regeneratingId.value = id
  error.value = null
  try {
    const response = await regenerateNodeDeployToken(id)
    installBox.value = {
      command: response.install_command,
      token: response.deploy_token,
    }
  } catch (err) {
    error.value = getErrorMessage(err, 'Deploy-Token konnte nicht erzeugt werden')
  } finally {
    regeneratingId.value = null
  }
}

async function copyCommand() {
  if (!installBox.value) return
  try {
    await navigator.clipboard.writeText(installBox.value.command)
    copied.value = true
    setTimeout(() => {
      copied.value = false
    }, 2000)
  } catch {
    error.value = 'Kopieren fehlgeschlagen — Befehl manuell markieren'
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>

    <div
      v-if="installBox"
      class="border border-panel-accent bg-panel-surface p-4 text-sm space-y-3"
    >
      <p class="font-medium text-panel-fg">Node-Installation (wie Pterodactyl)</p>
      <p class="text-panel-muted text-xs">
        Auf der Node-VM als root ausführen. Der Token ist nur einmal gültig.
      </p>
      <pre class="overflow-x-auto rounded bg-black/40 p-3 font-mono text-xs text-panel-fg">{{ installBox.command }}</pre>
      <div class="flex flex-wrap gap-2">
        <button class="panel-btn-primary text-xs" type="button" @click="copyCommand">
          {{ copied ? 'Kopiert' : 'Befehl kopieren' }}
        </button>
        <button class="panel-btn-secondary text-xs" type="button" @click="installBox = null">
          Schließen
        </button>
      </div>
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
      <template #actions="{ row }">
        <button
          class="panel-btn-secondary text-xs px-2 py-1"
          :disabled="regeneratingId === row.id"
          @click="regenerate(row.id)"
        >
          {{ regeneratingId === row.id ? '…' : 'Install-Befehl' }}
        </button>
      </template>
    </DataTable>
  </div>
</template>
