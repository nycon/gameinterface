<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink, RouterView, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const route = useRoute()
const auth = useAuthStore()

const serverId = computed(() => route.params.id as string | undefined)

const serverNav = computed(() => {
  if (!serverId.value) return []
  const base = `/client/servers/${serverId.value}`
  return [
    { to: `${base}/console`, label: 'Konsole' },
    { to: `${base}/files`, label: 'Dateien' },
    { to: `${base}/backups`, label: 'Backups' },
    { to: `${base}/databases`, label: 'Datenbanken' },
    { to: `${base}/ftp`, label: 'FTP' },
  ]
})

async function handleLogout() {
  await auth.logout()
  window.location.href = '/login'
}
</script>

<template>
  <div class="flex h-screen overflow-hidden">
    <aside class="panel-sidebar">
      <div class="border-b border-panel-border px-4 py-4">
        <div class="text-xs uppercase tracking-widest text-panel-muted">GamePanel</div>
        <div class="mt-0.5 text-sm font-semibold text-panel-accent">Meine Server</div>
      </div>

      <nav class="flex-1 overflow-y-auto py-2">
        <RouterLink
          to="/client/servers"
          class="panel-nav-link"
          :class="{ active: route.name === 'client-servers' }"
        >
          <span class="w-4 text-center font-mono text-xs opacity-70">▤</span>
          Server
        </RouterLink>

        <template v-if="serverId">
          <div class="mt-4 px-4 text-[10px] uppercase tracking-widest text-panel-muted">
            Server #{{ serverId }}
          </div>
          <RouterLink
            v-for="item in serverNav"
            :key="item.to"
            :to="item.to"
            class="panel-nav-link"
            :class="{ active: route.path === item.to }"
          >
            {{ item.label }}
          </RouterLink>
        </template>
      </nav>

      <div class="border-t border-panel-border p-4">
        <div class="text-xs text-panel-muted truncate">{{ auth.user?.name }}</div>
        <RouterLink
          to="/client/security"
          class="mt-1 block text-xs text-panel-accent hover:underline"
        >
          Sicherheit (2FA)
        </RouterLink>
        <RouterLink
          v-if="auth.user?.roles.includes('reseller')"
          to="/reseller"
          class="mt-1 block text-xs text-panel-accent hover:underline"
        >
          Reseller
        </RouterLink>
        <RouterLink
          v-if="auth.isAdmin"
          to="/admin"
          class="mt-1 block text-xs text-panel-accent hover:underline"
        >
          Admin-Bereich
        </RouterLink>
        <button class="mt-2 text-xs text-panel-muted hover:text-panel-text" @click="handleLogout">
          Abmelden
        </button>
      </div>
    </aside>

    <div class="flex flex-1 flex-col overflow-hidden">
      <header class="panel-header">
        <h1 class="text-sm font-semibold uppercase tracking-wide">
          {{ serverId ? `Server #${serverId}` : 'Server' }}
        </h1>
      </header>
      <main class="panel-content">
        <RouterView />
      </main>
    </div>
  </div>
</template>
