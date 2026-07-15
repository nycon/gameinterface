<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { fetchSettings, updateSettings } from '@/api/admin'
import { getErrorMessage } from '@/api/client'
import type { Setting } from '@/types'

const settings = ref<Setting[]>([])
const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const success = ref<string | null>(null)

async function load() {
  loading.value = true
  error.value = null
  try {
    settings.value = await fetchSettings()
  } catch (err) {
    settings.value = []
    error.value = getErrorMessage(err, 'Einstellungen konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  error.value = null
  success.value = null
  try {
    settings.value = await updateSettings(
      settings.value.map((s) => ({ key: s.key, value: s.value })),
    )
    success.value = 'Einstellungen gespeichert'
  } catch (err) {
    error.value = getErrorMessage(err, 'Speichern fehlgeschlagen')
  } finally {
    saving.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="max-w-lg space-y-4">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <p v-if="success" class="text-sm text-panel-success">{{ success }}</p>

    <div v-if="loading" class="text-sm text-panel-muted">Lade Einstellungen…</div>

    <form
      v-else
      class="space-y-4 border border-panel-border bg-panel-surface p-6"
      @submit.prevent="save"
    >
      <div v-if="settings.length === 0" class="text-sm text-panel-muted">
        Keine Einstellungen vorhanden
      </div>
      <div v-for="setting in settings" :key="setting.key">
        <label class="mb-1 block text-xs uppercase tracking-wide text-panel-muted">
          {{ setting.key }}
        </label>
        <input v-model="setting.value" class="panel-input" />
      </div>
      <button
        v-if="settings.length"
        type="submit"
        class="panel-btn-primary"
        :disabled="saving"
      >
        {{ saving ? 'Speichere…' : 'Speichern' }}
      </button>
    </form>
  </div>
</template>
