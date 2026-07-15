<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { createFtpAccount, deleteFtpAccount, fetchFtpAccounts } from '@/api/servers'
import { getErrorMessage } from '@/api/client'
import { useServersStore } from '@/stores/servers'

const route = useRoute()
const serverId = computed(() => Number(route.params.id))
const store = useServersStore()

const accounts = ref<Array<Record<string, unknown>>>([])
const host = ref<string | null>(null)
const port = ref(22)
const loading = ref(true)
const error = ref<string | null>(null)
const revealed = ref<{ username: string; password: string } | null>(null)

const connectHost = computed(
  () => host.value || store.currentServer?.node?.ip_address || '—',
)

async function load() {
  loading.value = true
  try {
    const res = await fetchFtpAccounts(serverId.value)
    accounts.value = Array.isArray(res) ? res : (res.data ?? [])
    if (!Array.isArray(res) && res.host) host.value = res.host
    if (!Array.isArray(res) && res.port) port.value = res.port
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
    if (res.host) host.value = res.host
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

onMounted(() => {
  store.loadServer(serverId.value).catch(() => {})
  load()
})
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div class="text-sm text-panel-muted">
        <p>SFTP auf dem Game-Node (OpenSSH, Port {{ port }})</p>
        <p class="mt-1 font-mono text-xs text-panel-accent">
          Host: {{ connectHost }} — Protokoll: SFTP
        </p>
      </div>
      <button class="panel-btn-primary text-sm" @click="create">Account erstellen</button>
    </div>
    <p v-if="revealed" class="border border-panel-border bg-panel-surface p-3 text-sm">
      Neu angelegt — in FileZilla/Cyberduck als <strong>SFTP</strong> verbinden:<br />
      <code>{{ connectHost }}</code>:<code>{{ port }}</code>
      User <code>{{ revealed.username }}</code>
      Pass <code>{{ revealed.password }}</code>
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
