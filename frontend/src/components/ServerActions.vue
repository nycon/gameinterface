<script setup lang="ts">
import { useServersStore } from '@/stores/servers'
import type { PowerAction } from '@/api/servers'
import type { Server } from '@/types'
import { isServerOnline, isServerStopped } from '@/types'

const props = defineProps<{
  server: Server
  admin?: boolean
}>()

const store = useServersStore()

async function run(action: PowerAction) {
  await store.performAction(props.server.id, action, props.admin ?? false)
}
</script>

<template>
  <div class="inline-flex flex-wrap items-center gap-1">
    <button
      v-if="isServerStopped(server.status)"
      class="panel-btn-primary text-xs px-2 py-1"
      :disabled="store.actionLoading === server.id"
      @click="run('start')"
    >
      Start
    </button>
    <button
      v-if="isServerOnline(server.status)"
      class="panel-btn-secondary text-xs px-2 py-1"
      :disabled="store.actionLoading === server.id"
      @click="run('stop')"
    >
      Stop
    </button>
    <button
      v-if="isServerOnline(server.status)"
      class="panel-btn-secondary text-xs px-2 py-1"
      :disabled="store.actionLoading === server.id"
      @click="run('restart')"
    >
      Restart
    </button>
    <button
      v-if="isServerOnline(server.status)"
      class="panel-btn-secondary text-xs px-2 py-1 text-panel-danger"
      :disabled="store.actionLoading === server.id"
      @click="run('kill')"
    >
      Kill
    </button>
    <button
      class="panel-btn-secondary text-xs px-2 py-1"
      :disabled="store.actionLoading === server.id"
      @click="run('install')"
    >
      Install
    </button>
    <button
      class="panel-btn-secondary text-xs px-2 py-1"
      :disabled="store.actionLoading === server.id"
      @click="run('update')"
    >
      Update
    </button>
  </div>
</template>
