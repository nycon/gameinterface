<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import ConsoleTerminal from '@/components/ConsoleTerminal.vue'

const route = useRoute()
const serverId = computed(() => Number(route.params.id))
</script>

<template>
  <ConsoleTerminal :server-id="serverId" />
</template>
