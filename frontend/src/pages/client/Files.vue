<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import FileTree from '@/components/FileTree.vue'
import { fetchFileContent, fetchServerFiles, writeServerFile } from '@/api/servers'
import { pollJob } from '@/api/jobs'
import { getErrorMessage } from '@/api/client'
import type { FileNode } from '@/types'

const route = useRoute()
const serverId = computed(() => Number(route.params.id))

const currentPath = ref('/')
const files = ref<FileNode[]>([])
const loading = ref(true)
const saving = ref(false)
const error = ref<string | null>(null)
const selectedFile = ref<FileNode | null>(null)
const editorContent = ref('')
const editorPath = ref('')

function mapEntries(entries: Array<Record<string, unknown>>): FileNode[] {
  return entries.map((e) => ({
    name: String(e.name ?? ''),
    path: String(e.path ?? ''),
    type: e.is_dir || e.type === 'directory' ? 'directory' : 'file',
    size: typeof e.size === 'number' ? e.size : undefined,
  }))
}

async function loadFiles(path: string) {
  loading.value = true
  error.value = null
  currentPath.value = path
  files.value = []
  try {
    const response = await fetchServerFiles(serverId.value, path)
    const job = await pollJob(response.job.uuid)
    if (job.status === 'failed') {
      throw new Error(job.error || 'Dateiliste fehlgeschlagen')
    }
    const entries = (job.result?.entries as Array<Record<string, unknown>>) || []
    files.value = mapEntries(entries)
  } catch (err) {
    error.value = getErrorMessage(err, 'Dateiliste konnte nicht geladen werden')
  } finally {
    loading.value = false
  }
}

async function onSelect(node: FileNode) {
  selectedFile.value = node
  if (node.type === 'directory') return
  loading.value = true
  error.value = null
  try {
    const response = await fetchFileContent(serverId.value, node.path)
    const job = await pollJob(response.job.uuid)
    if (job.status === 'failed') throw new Error(job.error || 'Lesen fehlgeschlagen')
    editorPath.value = node.path
    editorContent.value = String(job.result?.content ?? '')
  } catch (err) {
    error.value = getErrorMessage(err, 'Datei konnte nicht gelesen werden')
  } finally {
    loading.value = false
  }
}

async function saveFile() {
  if (!editorPath.value) return
  saving.value = true
  error.value = null
  try {
    const response = await writeServerFile(serverId.value, editorPath.value, editorContent.value)
    const job = await pollJob(response.job.uuid)
    if (job.status === 'failed') throw new Error(job.error || 'Schreiben fehlgeschlagen')
  } catch (err) {
    error.value = getErrorMessage(err, 'Speichern fehlgeschlagen')
  } finally {
    saving.value = false
  }
}

onMounted(() => loadFiles('/'))
</script>

<template>
  <div class="grid gap-4 lg:grid-cols-3">
    <div class="lg:col-span-1">
      <div class="mb-2 flex items-center justify-between">
        <span class="text-xs uppercase tracking-wide text-panel-muted">Dateien</span>
        <span class="font-mono text-xs text-panel-accent">{{ currentPath }}</span>
      </div>
      <p v-if="error" class="mb-2 text-xs text-panel-danger">{{ error }}</p>
      <FileTree
        :nodes="files"
        :loading="loading"
        @select="onSelect"
        @navigate="loadFiles"
      />
    </div>
    <div class="border border-panel-border bg-panel-surface p-4 lg:col-span-2">
      <div v-if="editorPath" class="space-y-3">
        <div class="flex items-center justify-between">
          <div class="font-mono text-sm">{{ editorPath }}</div>
          <button class="panel-btn-primary text-xs" :disabled="saving" @click="saveFile">
            {{ saving ? 'Speichern…' : 'Speichern' }}
          </button>
        </div>
        <textarea
          v-model="editorContent"
          class="panel-input min-h-[24rem] w-full font-mono text-xs"
          spellcheck="false"
        />
      </div>
      <div v-else class="text-sm text-panel-muted">Datei auswählen zum Bearbeiten.</div>
    </div>
  </div>
</template>
