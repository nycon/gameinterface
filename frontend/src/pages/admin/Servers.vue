<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { RouterLink } from 'vue-router'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import ServerActions from '@/components/ServerActions.vue'
import { useServersStore } from '@/stores/servers'
import { createAdminServer } from '@/api/servers'
import { fetchUsers, fetchTemplates } from '@/api/admin'
import apiClient from '@/api/client'
import { getErrorMessage } from '@/api/client'
import {
  serverGameName,
  serverNodeName,
  serverOwnerName,
  serverPort,
} from '@/types'
import type { Node, Template, User } from '@/types'

const store = useServersStore()
const showForm = ref(false)
const creating = ref(false)
const formError = ref<string | null>(null)
const users = ref<User[]>([])
const nodes = ref<Node[]>([])
const templates = ref<Template[]>([])

const form = reactive({
  name: '',
  user_id: 0,
  node_id: 0,
  game_template_id: 0,
  memory_max: '2048M',
  cpu_quota: '100%',
})

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'game', label: 'Spiel' },
  { key: 'status', label: 'Status' },
  { key: 'node', label: 'Node' },
  { key: 'port', label: 'Port' },
  { key: 'owner', label: 'Kunde' },
]

async function loadMeta() {
  const [u, t, n] = await Promise.all([
    fetchUsers(),
    fetchTemplates(),
    apiClient.get('/admin/nodes'),
  ])
  users.value = u.data
  templates.value = t.data
  nodes.value = n.data.data ?? n.data
  if (users.value[0]) form.user_id = users.value[0].id
  if (nodes.value[0]) form.node_id = nodes.value[0].id
  const mc = templates.value.find((tpl) => tpl.slug === 'minecraft')
  if (mc) form.game_template_id = mc.id
  else if (templates.value[0]) form.game_template_id = templates.value[0].id
}

async function createServer() {
  creating.value = true
  formError.value = null
  try {
    await createAdminServer({ ...form })
    showForm.value = false
    form.name = ''
    await store.loadServers(true)
  } catch (err) {
    formError.value = getErrorMessage(err, 'Server konnte nicht angelegt werden')
  } finally {
    creating.value = false
  }
}

onMounted(() => {
  store.loadServers(true).catch(() => {})
  loadMeta().catch(() => {})
})
</script>

<template>
  <div class="space-y-4">
    <div class="flex justify-between">
      <p v-if="store.error" class="text-sm text-panel-danger">{{ store.error }}</p>
      <button class="panel-btn-primary ml-auto text-sm" @click="showForm = !showForm">
        {{ showForm ? 'Abbrechen' : 'Server erstellen' }}
      </button>
    </div>

    <form
      v-if="showForm"
      class="grid gap-3 border border-panel-border bg-panel-surface p-4 md:grid-cols-2"
      @submit.prevent="createServer"
    >
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Name</label>
        <input v-model="form.name" required class="panel-input" />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Kunde</label>
        <select v-model.number="form.user_id" class="panel-input">
          <option v-for="u in users" :key="u.id" :value="u.id">{{ u.name }} ({{ u.email }})</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Node</label>
        <select v-model.number="form.node_id" class="panel-input">
          <option v-for="n in nodes" :key="n.id" :value="n.id">{{ n.name }}</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Template</label>
        <select v-model.number="form.game_template_id" class="panel-input">
          <option v-for="t in templates" :key="t.id" :value="t.id">{{ t.name }}</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">RAM</label>
        <input v-model="form.memory_max" class="panel-input" />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">CPU</label>
        <input v-model="form.cpu_quota" class="panel-input" />
      </div>
      <p v-if="formError" class="md:col-span-2 text-sm text-panel-danger">{{ formError }}</p>
      <button class="panel-btn-primary md:col-span-2" type="submit" :disabled="creating">
        {{ creating ? 'Erstelle…' : 'Anlegen & installieren' }}
      </button>
    </form>

    <DataTable :columns="columns" :rows="store.servers" :loading="store.loading">
      <template #cell-name="{ row }">
        <RouterLink :to="`/client/servers/${row.id}/console`" class="text-panel-accent hover:underline">
          {{ row.name }}
        </RouterLink>
      </template>
      <template #cell-game="{ row }">
        {{ serverGameName(row) }}
      </template>
      <template #cell-status="{ row }">
        <StatusBadge :status="row.status" />
      </template>
      <template #cell-node="{ row }">
        {{ serverNodeName(row) }}
      </template>
      <template #cell-port="{ row }">
        <span class="font-mono text-xs">{{ serverPort(row) }}</span>
      </template>
      <template #cell-owner="{ row }">
        {{ serverOwnerName(row) }}
      </template>
      <template #actions="{ row }">
        <ServerActions :server="row" admin />
      </template>
    </DataTable>
  </div>
</template>
