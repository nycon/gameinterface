<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import StatusBadge from '@/components/StatusBadge.vue'
import {
  createTemplate,
  deleteTemplate,
  fetchTemplates,
  updateTemplate,
} from '@/api/admin'
import { getErrorMessage } from '@/api/client'
import type { Template } from '@/types'

const templates = ref<Template[]>([])
const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const showForm = ref(false)
const editingId = ref<number | null>(null)

const form = reactive({
  name: '',
  slug: '',
  type: 'steam' as Template['type'],
  steam_app_id: '',
  is_active: true,
  yaml_definition: 'name: Neues Template\ntype: custom\n',
})

const formTitle = computed(() => (editingId.value ? 'Template bearbeiten' : 'Template anlegen'))

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'slug', label: 'Slug' },
  { key: 'type', label: 'Typ' },
  { key: 'steam_app_id', label: 'Steam App ID' },
  { key: 'is_active', label: 'Aktiv' },
]

async function load() {
  loading.value = true
  error.value = null
  try {
    const response = await fetchTemplates()
    templates.value = response.data
  } catch (err) {
    templates.value = []
    error.value = getErrorMessage(err, 'Templates konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editingId.value = null
  form.name = ''
  form.slug = ''
  form.type = 'steam'
  form.steam_app_id = ''
  form.is_active = true
  form.yaml_definition = 'name: Neues Template\ntype: custom\n'
  showForm.value = true
}

function openEdit(tpl: Template) {
  editingId.value = tpl.id
  form.name = tpl.name
  form.slug = tpl.slug
  form.type = tpl.type
  form.steam_app_id = tpl.steam_app_id ?? ''
  form.is_active = tpl.is_active
  form.yaml_definition = tpl.yaml_definition
  showForm.value = true
}

async function save() {
  saving.value = true
  error.value = null
  try {
    if (editingId.value) {
      await updateTemplate(editingId.value, {
        name: form.name,
        type: form.type,
        steam_app_id: form.steam_app_id || null,
        is_active: form.is_active,
        yaml_definition: form.yaml_definition,
      })
    } else {
      await createTemplate({
        name: form.name,
        slug: form.slug || undefined,
        type: form.type,
        steam_app_id: form.steam_app_id || null,
        is_active: form.is_active,
        yaml_definition: form.yaml_definition,
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

async function remove(tpl: Template) {
  if (!confirm(`Template „${tpl.name}“ löschen?`)) return
  try {
    await deleteTemplate(tpl.id)
    await load()
  } catch (err) {
    error.value = getErrorMessage(err, 'Löschen fehlgeschlagen')
  }
}

onMounted(load)
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between gap-3">
      <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
      <button class="panel-btn-primary ml-auto text-sm" @click="openCreate">Template anlegen</button>
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
        <label class="mb-1 block text-xs uppercase text-panel-muted">Slug</label>
        <input
          v-model="form.slug"
          class="panel-input"
          :disabled="!!editingId"
          placeholder="auto aus Name"
        />
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Typ</label>
        <select v-model="form.type" class="panel-input">
          <option value="steam">steam</option>
          <option value="minecraft">minecraft</option>
          <option value="url">url</option>
          <option value="custom">custom</option>
        </select>
      </div>
      <div>
        <label class="mb-1 block text-xs uppercase text-panel-muted">Steam App ID</label>
        <input v-model="form.steam_app_id" class="panel-input" />
      </div>
      <label class="flex items-center gap-2 text-sm md:col-span-2">
        <input v-model="form.is_active" type="checkbox" />
        Aktiv
      </label>
      <div class="md:col-span-2">
        <label class="mb-1 block text-xs uppercase text-panel-muted">YAML-Definition</label>
        <textarea
          v-model="form.yaml_definition"
          required
          class="panel-input min-h-[12rem] font-mono text-xs"
          spellcheck="false"
        />
      </div>
      <div class="md:col-span-2 flex gap-2">
        <button type="submit" class="panel-btn-primary" :disabled="saving">
          {{ saving ? 'Speichere…' : 'Speichern' }}
        </button>
        <button type="button" class="panel-btn-secondary" @click="showForm = false">Abbrechen</button>
      </div>
    </form>

    <DataTable :columns="columns" :rows="templates" :loading="loading" empty-text="Keine Templates — bitte anlegen oder Seeder ausführen">
      <template #cell-type="{ value }">
        <span class="font-mono text-xs">{{ value }}</span>
      </template>
      <template #cell-is_active="{ value }">
        <StatusBadge :status="value ? 'online' : 'offline'" />
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
