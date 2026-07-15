<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { createFtpAccount, deleteFtpAccount, fetchFtpAccounts } from '@/api/servers'
import { getErrorMessage } from '@/api/client'

const route = useRoute()
const serverId = computed(() => Number(route.params.id))

const accounts = ref<Array<Record<string, unknown>>>([])
const loading = ref(true)
const error = ref<string | null>(null)
const revealed = ref<{ username: string; password: string } | null>(null)

async function load() {
  loading.value = true
  try {
    accounts.value = await fetchFtpAccounts(serverId.value)
  } catch (err) {
    error.value = getErrorMessage(err, 'FTP-Accounts konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function create() {
  error.value = null
  revealed.value = null
  try {
    const res = await createFtpAccount(serverId.value)
    revealed.value = { username: res.ftp_account.username, password: res.password }
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Anlegen fehlgeschlagen')
  }
}

async function remove(id: number) {
  if (!confirm('SFTP-Account löschen?')) return
  try {
    await deleteFtpAccount(serverId.value, id)
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Löschen fehlgeschlagen')
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <p class="text-sm text-panel-muted">SFTP-Zugänge (Chroot auf dem Game-Node, Port 22)</p>
      <button class="panel-btn-primary text-sm" @click="create">Account erstellen</button>
    </div>
    <p v-if="revealed" class="text-sm text-panel-accent">
      Neu: <code>{{ revealed.username }}</code> / <code>{{ revealed.password }}</code>
    </p>
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <div v-if="loading" class="text-panel-muted">Lade…</div>
    <table v-else class="w-full text-sm">
      <thead class="text-left text-xs uppercase text-panel-muted">
        <tr>
          <th class="py-2">Username</th>
          <th>Home</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="acc in accounts" :key="String(acc.id)" class="border-t border-panel-border">
          <td class="py-2 font-mono">{{ acc.username }}</td>
          <td class="font-mono text-xs">{{ acc.home_path }}</td>
          <td>
            <button class="panel-btn-secondary text-xs" @click="remove(Number(acc.id))">Löschen</button>
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
