<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import apiClient from '@/api/client'
import { getErrorMessage } from '@/api/client'
import type { Server, User } from '@/types'

const users = ref<User[]>([])
const servers = ref<Server[]>([])
const error = ref<string | null>(null)
const form = reactive({ name: '', email: '', password: '' })

async function load() {
  try {
    const [u, s] = await Promise.all([
      apiClient.get('/reseller/users'),
      apiClient.get('/reseller/servers'),
    ])
    users.value = u.data.data ?? u.data
    servers.value = s.data.data ?? s.data
  } catch (err) {
    error.value = getErrorMessage(err, 'Reseller-Daten konnten nicht geladen werden')
  }
}

async function createUser() {
  error.value = null
  try {
    await apiClient.post('/reseller/users', form)
    form.name = ''
    form.email = ''
    form.password = ''
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Kunde anlegen fehlgeschlagen')
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-6">
    <h2 class="text-lg font-semibold">Reseller</h2>
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>

    <form class="grid gap-2 border border-panel-border bg-panel-surface p-4 md:grid-cols-4" @submit.prevent="createUser">
      <input v-model="form.name" required placeholder="Name" class="panel-input" />
      <input v-model="form.email" required type="email" placeholder="E-Mail" class="panel-input" />
      <input v-model="form.password" required type="password" minlength="10" placeholder="Passwort" class="panel-input" />
      <button class="panel-btn-primary" type="submit">Kunde anlegen</button>
    </form>

    <div class="grid gap-4 lg:grid-cols-2">
      <div>
        <h3 class="mb-2 text-sm uppercase text-panel-muted">Meine Kunden</h3>
        <ul class="space-y-1 text-sm">
          <li v-for="u in users" :key="u.id" class="border-b border-panel-border py-2">
            {{ u.name }} — {{ u.email }}
          </li>
        </ul>
      </div>
      <div>
        <h3 class="mb-2 text-sm uppercase text-panel-muted">Server im Scope</h3>
        <ul class="space-y-1 text-sm">
          <li v-for="s in servers" :key="s.id" class="border-b border-panel-border py-2">
            {{ s.name }} ({{ s.status }})
          </li>
        </ul>
      </div>
    </div>
  </div>
</template>
