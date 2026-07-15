<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import {
  createUser,
  deleteUser,
  fetchUsers,
  updateUser,
} from '@/api/admin'
import { getErrorMessage } from '@/api/client'
import type { User } from '@/types'
import { userDisplayRole } from '@/types'

const users = ref<User[]>([])
const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const showForm = ref(false)
const editingId = ref<number | null>(null)

const form = reactive({
  name: '',
  email: '',
  password: '',
  role: 'customer' as 'admin' | 'customer' | 'reseller',
})

const formTitle = computed(() => (editingId.value ? 'Benutzer bearbeiten' : 'Benutzer anlegen'))

function normalizeUser(u: User): User {
  return {
    ...u,
    roles: Array.isArray(u.roles)
      ? u.roles.map((r) => (typeof r === 'string' ? r : (r as { name: string }).name))
      : [],
  }
}

async function load() {
  loading.value = true
  error.value = null
  try {
    const response = await fetchUsers()
    users.value = response.data.map(normalizeUser)
  } catch (err) {
    users.value = []
    error.value = getErrorMessage(err, 'Benutzer konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editingId.value = null
  form.name = ''
  form.email = ''
  form.password = ''
  form.role = 'customer'
  showForm.value = true
}

function openEdit(user: User) {
  editingId.value = user.id
  form.name = user.name
  form.email = user.email
  form.password = ''
  const role = user.roles?.[0]
  form.role =
    role === 'admin' || role === 'reseller' || role === 'customer'
      ? role
      : user.is_admin
        ? 'admin'
        : 'customer'
  showForm.value = true
}

async function save() {
  saving.value = true
  error.value = null
  try {
    if (editingId.value) {
      const payload: Parameters<typeof updateUser>[1] = {
        name: form.name,
        email: form.email,
        role: form.role,
      }
      if (form.password) payload.password = form.password
      await updateUser(editingId.value, payload)
    } else {
      await createUser({
        name: form.name,
        email: form.email,
        password: form.password,
        role: form.role,
      })
    }
    showForm.value = false
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Speichern fehlgeschlagen')
  } finally {
    saving.value = false
  }
}

async function remove(user: User) {
  if (!confirm(`Benutzer „${user.email}“ wirklich löschen?`)) return
  try {
    await deleteUser(user.id)
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Löschen fehlgeschlagen')
  }
}

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'email', label: 'E-Mail' },
  { key: 'role', label: 'Rolle' },
  { key: 'is_admin', label: 'Admin' },
]

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
      <button class="panel-btn-primary ml-auto text-sm" @click="openCreate">Benutzer anlegen</button>
    </div>

    <form
      v-if="showForm"
      class="grid gap-3 border border-panel-border bg-panel-surface p-4 md:grid-cols-2"
      @submit.prevent="save"
    >
      <h3 class="md:col-span-2 text-sm font-semibold uppercase tracking-wide">{{ formTitle }}</h3>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Name</label>
        <input v-model="form.name" required class="panel-input" />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">E-Mail</label>
        <input v-model="form.email" type="email" required class="panel-input" />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">
          Passwort
          <span v-if="editingId" class="normal-case text-panel-muted">(leer = unverändert)</span>
        </label>
        <input
          v-model="form.password"
          type="password"
          class="panel-input"
          :required="!editingId"
          minlength="10"
          autocomplete="new-password"
        />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Rolle</label>
        <select v-model="form.role" class="panel-input">
          <option value="customer">Customer</option>
          <option value="reseller">Reseller</option>
          <option value="admin">Admin</option>
        </select>
      </div>
      <div class="md:col-span-2 flex gap-2">
        <button type="submit" class="panel-btn-primary" :disabled="saving">
          {{ saving ? 'Speichere…' : 'Speichern' }}
        </button>
        <button type="button" class="panel-btn-secondary" @click="showForm = false">Abbrechen</button>
      </div>
    </form>

    <DataTable :columns="columns" :rows="users" :loading="loading">
      <template #cell-role="{ row }">
        <span class="font-mono text-xs uppercase">
          {{ row.roles?.[0] || userDisplayRole(row) }}
        </span>
      </template>
      <template #cell-is_admin="{ value }">
        <span>{{ value ? 'Ja' : 'Nein' }}</span>
      </template>
      <template #actions="{ row }">
        <div class="flex gap-1">
          <button class="panel-btn-secondary text-xs px-2 py-1" @click="openEdit(row)">Edit</button>
          <button class="panel-btn-secondary text-xs px-2 py-1" @click="remove(row)">Löschen</button>
        </div>
      </template>
    </DataTable>
  </div>
</template>
