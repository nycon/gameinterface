import { defineStore } from 'pinia'
import { ref } from 'vue'
import * as serversApi from '@/api/servers'
import { getErrorMessage } from '@/api/client'
import type { PowerAction } from '@/api/servers'
import type { Server, ServerStatus } from '@/types'

export const useServersStore = defineStore('servers', () => {
  const servers = ref<Server[]>([])
  const currentServer = ref<Server | null>(null)
  const loading = ref(false)
  const actionLoading = ref<number | null>(null)
  const error = ref<string | null>(null)

  async function loadServers(admin = false) {
    loading.value = true
    error.value = null
    try {
      const response = admin
        ? await serversApi.fetchAdminServers()
        : await serversApi.fetchClientServers()
      servers.value = response.data
    } catch (err) {
      servers.value = []
      error.value = getErrorMessage(err, 'Server konnten nicht geladen werden')
      throw err
    } finally {
      loading.value = false
    }
  }

  async function loadServer(id: number) {
    loading.value = true
    error.value = null
    try {
      currentServer.value = await serversApi.fetchClientServer(id)
      return currentServer.value
    } catch (err) {
      currentServer.value = null
      error.value = getErrorMessage(err, 'Server konnte nicht geladen werden')
      throw err
    } finally {
      loading.value = false
    }
  }

  async function performAction(id: number, action: PowerAction, admin = false) {
    actionLoading.value = id
    error.value = null
    try {
      if (admin) {
        await serversApi.adminServerPower(id, action)
      } else {
        await serversApi.clientServerPower(id, action)
      }

      const statusMap: Partial<Record<PowerAction, ServerStatus>> = {
        start: 'starting',
        stop: 'stopping',
        restart: 'starting',
        kill: 'stopping',
        install: 'installing',
        update: 'installing',
      }
      const next = statusMap[action]
      const server = servers.value.find((s) => s.id === id)
      if (server && next) server.status = next
      if (currentServer.value?.id === id && next) currentServer.value.status = next
    } catch (err) {
      error.value = getErrorMessage(err, 'Aktion fehlgeschlagen')
      throw err
    } finally {
      actionLoading.value = null
    }
  }

  function updateServerStatus(id: number, status: ServerStatus) {
    const server = servers.value.find((s) => s.id === id)
    if (server) server.status = status
    if (currentServer.value?.id === id) currentServer.value.status = status
  }

  return {
    servers,
    currentServer,
    loading,
    actionLoading,
    error,
    loadServers,
    loadServer,
    performAction,
    updateServerStatus,
  }
})
