<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import { createImageServer, fetchImageServers, regenerateImageServerDeployToken } from '@/api/images'
import { testImageServer } from '@/api/admin'
import { getErrorMessage } from '@/api/client'
import type { ImageServer } from '@/types'

const servers = ref<ImageServer[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const showForm = ref(false)
const creating = ref(false)
const testingId = ref<number | null>(null)
const regeneratingId = ref<number | null>(null)
const testResult = ref<{ id: number; ok: boolean; message?: string } | null>(null)
const showAdvanced = ref(false)
const installBox = ref<{ command: string; token: string } | null>(null)
const copied = ref(false)

const form = ref({
  name: '',
  hostname: '',
  protocol: 'sftp' as const,
  port: 22,
  base_path: '/images',
  username: 'gamepanel-images',
  password: '',
  public_url: '',
})

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'hostname', label: 'Host' },
  { key: 'protocol', label: 'Protokoll' },
  { key: 'status', label: 'Status' },
  { key: 'is_active', label: 'Aktiv' },
]

async function load() {
  loading.value = true
  error.value = null
  try {
    const response = await fetchImageServers()
    servers.value = response.data
  } catch (err) {
    servers.value = []
    error.value = getErrorMessage(err, 'Image Server konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function submitCreate() {
  creating.value = true
  error.value = null
  try {
    const response = await createImageServer(
      showAdvanced.value
        ? {
            ...form.value,
            mode: 'manual',
            public_url: form.value.public_url || undefined,
          }
        : {
            name: form.value.name,
            mode: 'deploy',
          },
    )
    if (response.install_command && response.deploy_token) {
      installBox.value = {
        command: response.install_command,
        token: response.deploy_token,
      }
    }
    showForm.value = false
    showAdvanced.value = false
    form.value = {
      name: '',
      hostname: '',
      protocol: 'sftp',
      port: 22,
      base_path: '/images',
      username: 'gamepanel-images',
      password: '',
      public_url: '',
    }
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Image Server konnte nicht erstellt werden')
  } finally {
    creating.value = false
  }
}

async function regenerate(id: number) {
  regeneratingId.value = id
  error.value = null
  try {
    const response = await regenerateImageServerDeployToken(id)
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

async function runTest(id: number) {
  testingId.value = id
  testResult.value = null
  try {
    const result = await testImageServer(id)
    testResult.value = { id, ...result }
  } catch (err) {
    testResult.value = {
      id,
      ok: false,
      message: getErrorMessage(err, 'Verbindungstest fehlgeschlagen'),
    }
  } finally {
    testingId.value = null
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
    error.value = 'Kopieren fehlgeschlagen'
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
      <p class="font-medium text-panel-fg">Image-Server Installation</p>
      <p class="text-panel-muted text-xs">
        Auf der Image-Server-VM als root ausführen. Keys werden danach automatisch ans Panel gemeldet.
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

    <div
      v-if="testResult"
      class="border p-4 text-sm"
      :class="testResult.ok ? 'border-panel-success' : 'border-panel-danger'"
    >
      {{ testResult.ok ? 'Verbindung erfolgreich' : testResult.message ?? 'Verbindung fehlgeschlagen' }}
      <button class="panel-btn-secondary ml-2 text-xs" @click="testResult = null">Schließen</button>
    </div>

    <div class="flex justify-end">
      <button class="panel-btn-primary" @click="showForm = !showForm">
        {{ showForm ? 'Abbrechen' : 'Image Server hinzufügen' }}
      </button>
    </div>

    <form
      v-if="showForm"
      class="space-y-4 border border-panel-border bg-panel-surface p-4"
      @submit.prevent="submitCreate"
    >
      <div>
        <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Name</label>
        <input v-model="form.name" required class="panel-input" placeholder="z.B. images-01" />
      </div>

      <label class="flex items-center gap-2 text-sm text-panel-muted">
        <input v-model="showAdvanced" type="checkbox" />
        Manuell (bereits vorhandener Server mit Zugangsdaten)
      </label>

      <div v-if="showAdvanced" class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Hostname</label>
          <input v-model="form.hostname" required class="panel-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Protokoll</label>
          <select v-model="form.protocol" class="panel-input">
            <option value="sftp">SFTP</option>
            <option value="ftps">FTPS</option>
            <option value="ftp">FTP</option>
          </select>
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Port</label>
          <input v-model.number="form.port" required type="number" class="panel-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Basis-Pfad</label>
          <input v-model="form.base_path" required class="panel-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Benutzername</label>
          <input v-model="form.username" required class="panel-input" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Passwort</label>
          <input v-model="form.password" type="password" class="panel-input" />
        </div>
      </div>

      <button type="submit" class="panel-btn-primary" :disabled="creating">
        {{ creating ? 'Erstelle…' : showAdvanced ? 'Manuell speichern' : 'Anlegen & Install-Befehl' }}
      </button>
    </form>

    <DataTable :columns="columns" :rows="servers" :loading="loading">
      <template #cell-hostname="{ row }">
        <span class="font-mono text-xs">{{ row.hostname }}:{{ row.port }}</span>
      </template>
      <template #cell-status="{ value }">
        <span class="text-xs uppercase">{{ value ?? 'ready' }}</span>
      </template>
      <template #cell-is_active="{ value }">
        <span>{{ value ? 'Ja' : 'Nein' }}</span>
      </template>
      <template #actions="{ row }">
        <div class="flex gap-1">
          <button
            class="panel-btn-secondary text-xs px-2 py-1"
            :disabled="regeneratingId === row.id"
            @click="regenerate(row.id)"
          >
            {{ regeneratingId === row.id ? '…' : 'Install' }}
          </button>
          <button
            class="panel-btn-secondary text-xs px-2 py-1"
            :disabled="testingId === row.id || row.status === 'pending'"
            @click="runTest(row.id)"
          >
            {{ testingId === row.id ? '…' : 'Test' }}
          </button>
        </div>
      </template>
    </DataTable>
  </div>
</template>
