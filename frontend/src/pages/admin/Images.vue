<script setup lang="ts">
import { onMounted, ref } from 'vue'
import DataTable from '@/components/DataTable.vue'
import { fetchImages } from '@/api/images'
import { getErrorMessage } from '@/api/client'
import type { GameImage } from '@/types'

const images = ref<GameImage[]>([])
const loading = ref(true)
const error = ref<string | null>(null)

const columns = [
  { key: 'name', label: 'Name' },
  { key: 'slug', label: 'Slug' },
  { key: 'template', label: 'Template' },
  { key: 'versions', label: 'Versionen' },
  { key: 'description', label: 'Beschreibung' },
]

onMounted(async () => {
  try {
    const response = await fetchImages()
    images.value = response.data
  } catch (err) {
    images.value = []
    error.value = getErrorMessage(err, 'Images konnten nicht geladen werden')
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div class="space-y-4">
    <p v-if="error" class="text-sm text-panel-danger">{{ error }}</p>
    <DataTable :columns="columns" :rows="images" :loading="loading">
      <template #cell-template="{ row }">
        {{ row.template?.name ?? '—' }}
      </template>
      <template #cell-versions="{ row }">
        <span class="font-mono text-xs">{{ row.versions?.length ?? 0 }}</span>
      </template>
    </DataTable>
  </div>
</template>
