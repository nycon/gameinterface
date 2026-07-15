import apiClient from './client'
import type {
  Backup,
  DashboardResponse,
  PaginatedResponse,
  Server,
} from '@/types'

export type PowerAction = 'start' | 'stop' | 'restart' | 'kill' | 'install' | 'update'

export async function fetchClientServers(page = 1): Promise<PaginatedResponse<Server>> {
  const { data } = await apiClient.get<PaginatedResponse<Server>>('/client/servers', {
    params: { page },
  })
  return data
}

export async function fetchAdminServers(page = 1): Promise<PaginatedResponse<Server>> {
  const { data } = await apiClient.get<PaginatedResponse<Server>>('/admin/servers', {
    params: { page },
  })
  return data
}

export async function fetchClientServer(id: number): Promise<Server> {
  const { data } = await apiClient.get<Server>(`/client/servers/${id}`)
  return data
}

export async function createAdminServer(payload: {
  name: string
  user_id: number
  node_id: number
  game_template_id: number
  image_version_id?: number | null
  cpu_quota?: string
  memory_max?: string
  startup_command?: string
}): Promise<{ server: Server; job: { uuid: string } | null }> {
  const { data } = await apiClient.post('/admin/servers', payload)
  return data
}

export async function deleteAdminServer(id: number): Promise<void> {
  await apiClient.delete(`/admin/servers/${id}`)
}

export async function clientServerPower(id: number, action: PowerAction): Promise<void> {
  await apiClient.post(`/client/servers/${id}/${action}`)
}

export async function adminServerPower(id: number, action: PowerAction): Promise<void> {
  await apiClient.post(`/admin/servers/${id}/${action}`)
}

export async function fetchDashboard(): Promise<DashboardResponse> {
  const { data } = await apiClient.get<DashboardResponse>('/admin/dashboard')
  return data
}

export async function fetchServerFiles(
  serverId: number,
  path = '/',
): Promise<{ job: { uuid: string }; message: string }> {
  const { data } = await apiClient.get<{ job: { uuid: string }; message: string }>(
    `/client/servers/${serverId}/files`,
    { params: { path } },
  )
  return data
}

export async function fetchFileContent(
  serverId: number,
  path: string,
): Promise<{ job: { uuid: string } }> {
  const { data } = await apiClient.get<{ job: { uuid: string } }>(
    `/client/servers/${serverId}/files/content`,
    { params: { path } },
  )
  return data
}

export async function writeServerFile(
  serverId: number,
  path: string,
  content: string,
): Promise<{ job: { uuid: string } }> {
  const { data } = await apiClient.post<{ job: { uuid: string } }>(
    `/client/servers/${serverId}/files/write`,
    { path, content },
  )
  return data
}

export async function fetchBackups(serverId: number, page = 1): Promise<PaginatedResponse<Backup>> {
  const { data } = await apiClient.get<PaginatedResponse<Backup>>(
    `/client/servers/${serverId}/backups`,
    { params: { page } },
  )
  return data
}

export async function createBackup(serverId: number, name?: string): Promise<{ job: { uuid: string } }> {
  const { data } = await apiClient.post(`/client/servers/${serverId}/backups`, { name })
  return data
}

export async function restoreBackup(serverId: number, backupId: number): Promise<{ job: { uuid: string } }> {
  const { data } = await apiClient.post(`/client/servers/${serverId}/backups/${backupId}/restore`)
  return data
}

export async function deleteBackup(serverId: number, backupId: number): Promise<void> {
  await apiClient.delete(`/client/servers/${serverId}/backups/${backupId}`)
}

export async function fetchDatabases(serverId: number): Promise<{
  data: Array<Record<string, unknown>>
  phpmyadmin_url?: string | null
}> {
  const { data } = await apiClient.get(`/client/servers/${serverId}/databases`)
  if (Array.isArray(data)) {
    return { data, phpmyadmin_url: null }
  }
  return data
}

export async function createDatabase(
  serverId: number,
  payload: { name: string; username?: string; password?: string },
) {
  const { data } = await apiClient.post(`/client/servers/${serverId}/databases`, payload)
  return data
}

export async function revealDatabase(serverId: number, databaseId: number) {
  const { data } = await apiClient.get<{
    password: string
    phpmyadmin_url?: string | null
  }>(`/client/servers/${serverId}/databases/${databaseId}/reveal`)
  return data
}

export async function deleteDatabase(serverId: number, databaseId: number) {
  const { data } = await apiClient.delete(`/client/servers/${serverId}/databases/${databaseId}`)
  return data
}

export async function fetchFtpAccounts(serverId: number) {
  const { data } = await apiClient.get(`/client/servers/${serverId}/ftp-accounts`)
  return data
}

export async function createFtpAccount(serverId: number, payload: { username?: string; password?: string } = {}) {
  const { data } = await apiClient.post(`/client/servers/${serverId}/ftp-accounts`, payload)
  return data
}

export async function deleteFtpAccount(serverId: number, accountId: number) {
  const { data } = await apiClient.delete(`/client/servers/${serverId}/ftp-accounts/${accountId}`)
  return data
}

export async function sendConsoleCommand(serverId: number, command: string) {
  const { data } = await apiClient.post(`/client/servers/${serverId}/console/command`, { command })
  return data
}

export async function fetchConsoleHistory(serverId: number, limit = 100) {
  const { data } = await apiClient.get(`/client/servers/${serverId}/console/history`, {
    params: { limit },
  })
  return data
}
