<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import { fetchImages, registerImage } from '@/api/images'
import { fetchTemplates } from '@/api/admin'
import { getErrorMessage } from '@/api/client'
import type { GameImage, Template } from '@/types'

const images = ref<GameImage[]>([])
const templates = ref<Template[]>([])
const loading = ref(true)
const error = ref<string | null>(null)
const success = ref<string | null>(null)
const showForm = ref(false)
const creating = ref(false)

const form = ref({
  slug: 'cs2',
  version: '1.0.0',
  name: '',
  game_template_id: null as number | null,
  checksum_sha256: '',
  size_bytes: 0,
})

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'slug', label: 'Slug' },
  { key: 'template', label: 'Template' },
  { key: 'versions', label: 'Versionen' },
  { key: 'description', label: 'Beschreibung' },
]

async function load() {
  loading.value = true
  error.value = null
  try {
    const [img, tpl] = await Promise.all([fetchImages(), fetchTemplates()])
    images.value = img.data
    templates.value = tpl.data
    if (!form.value.game_template_id && templates.value[0]) {
      form.value.game_template_id = templates.value[0].id
    }
  } catch (err) {
    images.value = []
    error.value = getErrorMessage(err, 'Images konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function submitRegister() {
  creating.value = true
  error.value = null
  success.value = null
  try {
    const sha = form.value.checksum_sha256.trim().toLowerCase()
    if (!/^[a-f0-9]{64}$/.test(sha)) {
      throw new Error('SHA256 muss genau 64 Hex-Zeichen sein (Inhalt der .sha256-Datei)')
    }
    const result = await registerImage({
      slug: form.value.slug.trim(),
      version: form.value.version.trim(),
      name: form.value.name.trim() || undefined,
      game_template_id: form.value.game_template_id,
      checksum_sha256: sha,
      size_bytes: Number(form.value.size_bytes) || 0,
      is_latest: true,
    })
    success.value = `Registriert: ${result.image.slug}@${result.version.version}`
    showForm.value = false
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Registrierung fehlgeschlagen')
  } finally {
    creating.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <p v-if="success" class="text-sm text-panel-success">{{ success }}</p>

    <div class="border border-panel-border bg-panel-surface p-4 text-sm text-panel-muted space-y-2">
      <p class="font-medium text-panel-fg">So erscheinen Images im Panel</p>
      <ol class="list-decimal pl-5 space-y-1">
        <li>Auf dem Image-Server bauen: <code class="font-mono text-xs">gp-image build cs2 --version 1.0.0</code></li>
        <li>SHA256 lesen: <code class="font-mono text-xs">cat /srv/gamepanel-images/games/cs2/versions/1.0.0/cs2-1.0.0.sha256</code></li>
        <li>Hier unten registrieren (Slug + Version + SHA256)</li>
      </ol>
    </div>

    <div class="flex justify-end">
      <button class="panel-btn-primary" type="button" @click="showForm = !showForm">
        {{ showForm ? 'Abbrechen' : 'Image registrieren' }}
      </button>
    </div>

    <form
      v-if="showForm"
      class="space-y-4 border border-panel-border bg-panel-surface p-4"
      @submit.prevent="submitRegister"
    >
      <div class="grid gap-4 sm:grid-cols-2">
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Slug</label>
          <input v-model="form.slug" required class="panel-input font-mono" placeholder="cs2" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Version</label>
          <input v-model="form.version" required class="panel-input font-mono" placeholder="1.0.0" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Name (optional)</label>
          <input v-model="form.name" class="panel-input" placeholder="Counter-Strike 2" />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Template</label>
          <select v-model="form.game_template_id" class="panel-input">
            <option :value="null">— keins —</option>
            <option v-for="t in templates" :key="t.id" :value="t.id">{{ t.name }} ({{ t.slug }})</option>
          </select>
        </div>
        <div class="sm:col-span-2">
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">SHA256</label>
          <input
            v-model="form.checksum_sha256"
            required
            class="panel-input font-mono text-xs"
            placeholder="Inhalt von *.sha256"
          />
        </div>
        <div>
          <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">Größe (Bytes, optional)</label>
          <input v-model.number="form.size_bytes" type="number" min="0" class="panel-input" />
        </div>
      </div>
      <button type="submit" class="panel-btn-primary" :disabled="creating">
        {{ creating ? 'Speichere…' : 'Im Panel registrieren' }}
      </button>
    </form>

    <DataTable :columns="columns" :rows="images" :loading="loading" empty-text="Keine Images — nach dem Build hier registrieren">
      <template #cell-template="{ row }">
        {{ row.template?.name ?? '—' }}
      </template>
      <template #cell-versions="{ row }">
        <span class="font-mono text-xs">
          {{ row.versions?.map((v) => v.version).join(', ') || (row.versions?.length ?? 0) }}
        </span>
      </template>
    </DataTable>
  </div>
</template>
