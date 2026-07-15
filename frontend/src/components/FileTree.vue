<script setup lang="ts">
import { ref } from 'vue'
import type { FileNode } from '@/types'

defineProps<{
  nodes: FileNode[]
  loading?: boolean
}>()

const emit = defineEmits<{
  select: [node: FileNode]
  navigate: [path: string]
}>()

const expanded = ref<Set<string>>(new Set())

function toggle(node: FileNode) {
  if (node.type !== 'directory') {
    emit('select', node)
    return
  }
  if (expanded.value.has(node.path)) {
    expanded.value.delete(node.path)
  } else {
    expanded.value.add(node.path)
    emit('navigate', node.path)
  }
}

function formatSize(bytes?: number) {
  if (bytes == null) return '—'
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`
}
</script>

<template>
  <div class="border border-panel-border font-mono text-sm">
    <div v-if="loading" class="px-4 py-6 text-panel-muted">Lade Dateien…</div>
    <div v-else-if="nodes.length === 0" class="px-4 py-6 text-panel-muted">Verzeichnis leer</div>
    <ul v-else>
      <li
        v-for="node in nodes"
        :key="node.path"
        class="flex cursor-pointer items-center gap-2 border-b border-panel-border/40 px-4 py-1.5 hover:bg-panel-surface"
        @click="toggle(node)"
      >
        <span class="text-panel-accent">{{ node.type === 'directory' ? '▸' : '·' }}</span>
        <span :class="node.type === 'directory' ? 'text-panel-text' : 'text-panel-muted'">
          {{ node.name }}
        </span>
        <span v-if="node.type === 'file'" class="ml-auto text-xs text-panel-muted">
          {{ formatSize(node.size) }}
        </span>
      </li>
    </ul>
  </div>
</template>
