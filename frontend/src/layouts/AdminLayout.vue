<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink, RouterView, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const route = useRoute()
const auth = useAuthStore()

const navItems = [
  { to: '/admin', label: 'Dashboard', icon: '▣', exact: true },
  { to: '/admin/nodes', label: 'Nodes', icon: '⬡' },
  { to: '/admin/servers', label: 'Server', icon: '▤' },
  { to: '/admin/allocations', label: 'Ports', icon: '◎' },
  { to: '/admin/databases', label: 'Datenbanken', icon: '◇' },
  { to: '/admin/image-servers', label: 'Image Server', icon: '◫' },
  { to: '/admin/images', label: 'Images', icon: '◧' },
  { to: '/admin/templates', label: 'Templates', icon: '▦' },
  { to: '/admin/users', label: 'Benutzer', icon: '◉' },
  { to: '/admin/jobs', label: 'Jobs', icon: '↻' },
  { to: '/admin/audit-logs', label: 'Audit Log', icon: '☰' },
  { to: '/admin/settings', label: 'Einstellungen', icon: '⚙' },
]

const pageTitle = computed(() => {
  const item = navItems.find((n) =>
    n.exact ? route.path === n.to : route.path.startsWith(n.to),
  )
  return item?.label ?? 'Admin'
})

function isActive(item: (typeof navItems)[number]) {
  if (item.exact) return route.path === item.to
  return route.path.startsWith(item.to)
}

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
        <div class="mt-0.5 text-sm font-semibold text-panel-accent">Administration</div>
      </div>

      <nav class="flex-1 overflow-y-auto py-2">
        <RouterLink
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="panel-nav-link"
          :class="{ active: isActive(item) }"
        >
          <span class="w-4 text-center font-mono text-xs opacity-70">{{ item.icon }}</span>
          {{ item.label }}
        </RouterLink>
      </nav>

      <div class="border-t border-panel-border p-4">
        <div class="text-xs text-panel-muted truncate">{{ auth.user?.email }}</div>
        <button class="mt-2 text-xs text-panel-accent hover:underline" @click="handleLogout">
          Abmelden
        </button>
      </div>
    </aside>

    <div class="flex flex-1 flex-col overflow-hidden">
      <header class="panel-header">
        <h1 class="text-sm font-semibold uppercase tracking-wide">{{ pageTitle }}</h1>
        <div class="text-xs text-panel-muted font-mono">v0.1.0</div>
      </header>
      <main class="panel-content">
        <RouterView />
      </main>
    </div>
  </div>
</template>
