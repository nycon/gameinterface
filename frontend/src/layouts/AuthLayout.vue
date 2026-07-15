<script setup lang="ts">
import { RouterView } from 'vue-router'
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-panel-bg p-4">
    <div class="w-full max-w-sm">
      <div class="mb-8 text-center">
        <div class="text-xs uppercase tracking-[0.3em] text-panel-muted">GamePanel</div>
        <h1 class="mt-2 text-xl font-semibold text-panel-text">Anmeldung</h1>
      </div>
      <RouterView />
    </div>
  </div>
</template>
