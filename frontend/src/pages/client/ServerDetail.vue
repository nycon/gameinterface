<script setup lang="ts">
import { computed, onMounted } from 'vue'
import { RouterLink, RouterView, useRoute } from 'vue-router'
import StatusBadge from '@/components/StatusBadge.vue'
import ServerActions from '@/components/ServerActions.vue'
import { useServersStore } from '@/stores/servers'
import { serverGameName, serverPort, serverConnectAddress } from '@/types'

const route = useRoute()
const store = useServersStore()

const serverId = computed(() => Number(route.params.id))

const tabs = computed(() => [
  { to: `/client/servers/${serverId.value}/console`, label: 'Konsole' },
  { to: `/client/servers/${serverId.value}/files`, label: 'Dateien' },
  { to: `/client/servers/${serverId.value}/backups`, label: 'Backups' },
  { to: `/client/servers/${serverId.value}/databases`, label: 'Datenbanken' },
  { to: `/client/servers/${serverId.value}/ftp`, label: 'FTP' },
])

onMounted(() => {
  store.loadServer(serverId.value).catch(() => {})
})
</script>

<template>
  <div v-if="store.loading && !store.currentServer" class="text-panel-muted">Lade Server…</div>
  <div v-else-if="store.error && !store.currentServer" class="text-panel-danger">
    {{ store.error }}
  </div>
  <div v-else-if="store.currentServer" class="space-y-4">
    <div class="flex flex-wrap items-center justify-between gap-4 border border-panel-border bg-panel-surface px-4 py-3">
      <div>
        <h2 class="text-lg font-semibold">{{ store.currentServer.name }}</h2>
        <div class="mt-1 flex flex-wrap items-center gap-3 text-sm text-panel-muted">
          <span>{{ serverGameName(store.currentServer) }}</span>
          <span class="font-mono text-panel-accent">{{ serverConnectAddress(store.currentServer) }}</span>
          <span class="font-mono text-xs">Port {{ serverPort(store.currentServer) }}</span>
          <StatusBadge :status="store.currentServer.status" />
        </div>
      </div>
      <ServerActions :server="store.currentServer" />
    </div>

    <nav class="flex gap-1 border-b border-panel-border">
      <RouterLink
        v-for="tab in tabs"
        :key="tab.to"
        :to="tab.to"
        class="border-b-2 border-transparent px-4 py-2 text-sm text-panel-muted hover:text-panel-text"
        active-class="!text-panel-accent !border-panel-accent"
      >
        {{ tab.label }}
      </RouterLink>
    </nav>

    <RouterView />
  </div>
</template>
