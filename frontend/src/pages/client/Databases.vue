<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { createDatabase, deleteDatabase, fetchDatabases } from '@/api/servers'
import { getErrorMessage } from '@/api/client'

const route = useRoute()
const serverId = computed(() => Number(route.params.id))

const databases = ref<Array<Record<string, unknown>>>([])
const loading = ref(true)
const error = ref<string | null>(null)
const plaintextPassword = ref<string | null>(null)
const name = ref('')

async function load() {
  loading.value = true
  try {
    databases.value = await fetchDatabases(serverId.value)
  } catch (err) {
    error.value = getErrorMessage(err, 'Datenbanken konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function create() {
  error.value = null
  plaintextPassword.value = null
  try {
    const res = await createDatabase(serverId.value, { name: name.value })
    plaintextPassword.value = res.password
    name.value = ''
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Anlegen fehlgeschlagen')
  }
}

async function remove(id: number) {
  if (!confirm('Datenbank löschen?')) return
  try {
    await deleteDatabase(serverId.value, id)
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Löschen fehlgeschlagen')
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <form class="flex flex-wrap items-end gap-2 border border-panel-border bg-panel-surface p-4" @submit.prevent="create">
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">DB-Name</label>
        <input v-model="name" required pattern="[A-Za-z0-9_]+" class="panel-input" />
      </div>
      <button class="panel-btn-primary" type="submit">Anlegen</button>
    </form>
    <p v-if="plaintextPassword" class="text-sm text-panel-accent">
      Passwort (einmalig): <code class="font-mono">{{ plaintextPassword }}</code>
    </p>
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <div v-if="loading" class="text-panel-muted">Lade…</div>
    <table v-else class="w-full text-sm">
      <thead class="text-left text-xs uppercase text-panel-muted">
        <tr>
          <th class="py-2">Name</th>
          <th>User</th>
          <th>Host</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="db in databases" :key="String(db.id)" class="border-t border-panel-border">
          <td class="py-2 font-mono">{{ db.name }}</td>
          <td>{{ db.username }}</td>
          <td class="font-mono text-xs">{{ db.host }}:{{ db.port }}</td>
          <td>
            <button class="panel-btn-secondary text-xs" @click="remove(Number(db.id))">Löschen</button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
