<script setup lang="ts" generic="T extends object">
defineProps<{
  columns: { key: string; label: string; class?: string }[]
  rows: T[]
  loading?: boolean
  emptyText?: string
}>()

function cellValue(row: T, key: string): unknown {
  return (row as Record<string, unknown>)[key]
}
</script>

<template>
  <div class="border border-panel-border">
    <div v-if="loading" class="px-4 py-8 text-center text-sm text-panel-muted">
      Lade Daten…
    </div>
    <table v-else class="panel-table">
      <thead>
        <tr>
          <th v-for="col in columns" :key="col.key" :class="col.class">
            {{ col.label }}
          </th>
          <th v-if="$slots.actions" class="w-32">Aktionen</th>
        </tr>
      </thead>
      <tbody>
        <tr v-if="rows.length === 0">
          <td :colspan="columns.length + ($slots.actions ? 1 : 0)" class="py-8 text-center text-panel-muted">
            {{ emptyText ?? 'Keine Einträge' }}
          </td>
        </tr>
        <tr v-for="(row, idx) in rows" :key="idx">
          <td v-for="col in columns" :key="col.key" :class="col.class">
            <slot :name="`cell-${col.key}`" :row="row" :value="cellValue(row, col.key)">
              {{ cellValue(row, col.key) }}
            </slot>
          </td>
          <td v-if="$slots.actions">
            <slot name="actions" :row="row" />
          </td>
        </tr>
      </tbody>
    </table>
  </div>
</template>
