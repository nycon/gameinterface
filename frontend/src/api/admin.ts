import apiClient from './client'
import type {
  AuditLog,
  PaginatedResponse,
  PanelJob,
  Setting,
  Template,
  User,
} from '@/types'

export async function fetchUsers(page = 1): Promise<PaginatedResponse<User>> {
  const { data } = await apiClient.get<PaginatedResponse<User>>('/admin/users', {
    params: { page },
  })
  return data
}

export async function createUser(payload: {
  name: string
  email: string
  password: string
  role?: 'admin' | 'customer' | 'reseller'
  is_admin?: boolean
  reseller_id?: number | null
}): Promise<User> {
  const { data } = await apiClient.post<User>('/admin/users', payload)
  return data
}

export async function updateUser(
  id: number,
  payload: {
    name?: string
    email?: string
    password?: string
    role?: 'admin' | 'customer' | 'reseller'
    is_admin?: boolean
    reseller_id?: number | null
  },
): Promise<User> {
  const { data } = await apiClient.put<User>(`/admin/users/${id}`, payload)
  return data
}

export async function deleteUser(id: number): Promise<void> {
  await apiClient.delete(`/admin/users/${id}`)
}

export async function fetchJobs(page = 1): Promise<PaginatedResponse<PanelJob>> {
  const { data } = await apiClient.get<PaginatedResponse<PanelJob>>('/admin/jobs', {
    params: { page },
  })
  return data
}

export async function fetchAuditLogs(page = 1): Promise<PaginatedResponse<AuditLog>> {
  const { data } = await apiClient.get<PaginatedResponse<AuditLog>>('/admin/audit-logs', {
    params: { page },
  })
  return data
}

export async function fetchTemplates(page = 1): Promise<PaginatedResponse<Template>> {
  const { data } = await apiClient.get<PaginatedResponse<Template>>('/admin/templates', {
    params: { page },
  })
  return data
}

export async function createTemplate(payload: {
  name: string
  slug?: string
  type: Template['type']
  yaml_definition: string
  steam_app_id?: string | null
  is_active?: boolean
}): Promise<Template> {
  const { data } = await apiClient.post<Template>('/admin/templates', payload)
  return data
}

export async function updateTemplate(
  id: number,
  payload: Partial<{
    name: string
    type: Template['type']
    yaml_definition: string
    steam_app_id: string | null
    is_active: boolean
  }>,
): Promise<Template> {
  const { data } = await apiClient.put<Template>(`/admin/templates/${id}`, payload)
  return data
}

export async function deleteTemplate(id: number): Promise<void> {
  await apiClient.delete(`/admin/templates/${id}`)
}

export async function fetchSettings(): Promise<Setting[]> {
  const { data } = await apiClient.get<Setting[]>('/admin/settings')
  return data
}

export async function updateSettings(settings: { key: string; value: string | null }[]): Promise<Setting[]> {
  const { data } = await apiClient.put<Setting[]>('/admin/settings', { settings })
  return data
}

export async function testImageServer(id: number): Promise<{ ok: boolean; message?: string }> {
  const { data } = await apiClient.post<{ ok: boolean; message?: string }>(
    `/admin/image-servers/${id}/test`,
  )
  return data
}

export async function fetchAdminDatabases(page = 1) {
  const { data } = await apiClient.get('/admin/databases', { params: { page } })
  return data as PaginatedResponse<{
    id: number
    name: string
    username: string
    host: string
    port: number
    engine: string
    server?: {
      id: number
      name: string
      owner?: { id: number; name: string; email?: string }
      node?: { id: number; name: string; ip_address?: string; phpmyadmin_url?: string }
    }
  }>
}

export async function revealAdminDatabase(id: number) {
  const { data } = await apiClient.get<{
    password: string
    phpmyadmin_url?: string | null
  }>(`/admin/databases/${id}/reveal`)
  return data
}

export async function fetchNodeDbAccess(nodeId: number) {
  const { data } = await apiClient.get<{
    phpmyadmin_url: string | null
    username: string
    password: string | null
  }>('/admin/databases/node-access', { params: { node_id: nodeId } })
  return data
}
