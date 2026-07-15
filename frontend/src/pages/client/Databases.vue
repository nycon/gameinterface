<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import {
  createDatabase,
  deleteDatabase,
  fetchDatabases,
  revealDatabase,
} from '@/api/servers'
import { getErrorMessage } from '@/api/client'

const route = useRoute()
const serverId = computed(() => Number(route.params.id))

const databases = ref<Array<Record<string, unknown>>>([])
const phpmyadminUrl = ref<string | null>(null)
const loading = ref(true)
const error = ref<string | null>(null)
const plaintextPassword = ref<string | null>(null)
const revealed = ref<Record<number, string>>({})
const name = ref('')

async function load() {
  loading.value = true
  try {
    const res = await fetchDatabases(serverId.value)
    databases.value = res.data ?? (Array.isArray(res) ? res : [])
    phpmyadminUrl.value = res.phpmyadmin_url ?? null
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

async function openPma(id: number, username: string) {
  try {
    const res = await revealDatabase(serverId.value, id)
    revealed.value = { ...revealed.value, [id]: res.password }
    plaintextPassword.value = null
    const url = res.phpmyadmin_url || phpmyadminUrl.value
    if (url) {
      window.open(url, '_blank', 'noopener')
      alert(
        `phpMyAdmin geöffnet.\n\nLogin:\nUser: ${username}\nPasswort: ${res.password}\n\nDu siehst nur diese eine Datenbank.`,
      )
    }
  } catch (err) {
    error.value = getErrorMessage(err, 'Zugang fehlgeschlagen')
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <p class="text-sm text-panel-muted">
      Datenbanken werden auf dem Game-Node angelegt. Über phpMyAdmin (Cookie-Login) siehst du nur
      deine eigene DB.
      <a
        v-if="phpmyadminUrl"
        :href="phpmyadminUrl"
        target="_blank"
        rel="noopener"
        class="text-panel-accent hover:underline ml-1"
      >{{ phpmyadminUrl }}</a>
    </p>

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
          <td class="space-x-1">
            <button
              class="panel-btn-secondary text-xs"
              type="button"
              @click="openPma(Number(db.id), String(db.username))"
            >
              phpMyAdmin
            </button>
            <button class="panel-btn-secondary text-xs text-panel-danger" type="button" @click="remove(Number(db.id))">
              Löschen
            </button>
            <span v-if="revealed[Number(db.id)]" class="font-mono text-xs text-panel-accent">
              {{ revealed[Number(db.id)] }}
            </span>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
