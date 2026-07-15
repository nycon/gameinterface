import apiClient from './client'
import type { CreateNodeResponse, Node, PaginatedResponse } from '@/types'

export async function fetchNodes(page = 1): Promise<PaginatedResponse<Node>> {
  const { data } = await apiClient.get<PaginatedResponse<Node>>('/admin/nodes', {
    params: { page },
  })
  return data
}

export async function fetchNode(id: number): Promise<Node> {
  const { data } = await apiClient.get<Node>(`/admin/nodes/${id}`)
  return data
}

export async function createNode(payload: {
  name: string
  hostname: string
  ip_address: string
}): Promise<CreateNodeResponse> {
  const { data } = await apiClient.post<CreateNodeResponse>('/admin/nodes', payload)
  return data
}

export async function updateNode(id: number, payload: Partial<Node>): Promise<Node> {
  const { data } = await apiClient.put<Node>(`/admin/nodes/${id}`, payload)
  return data
}

export async function deleteNode(id: number): Promise<void> {
  await apiClient.delete(`/admin/nodes/${id}`)
}

export async function regenerateNodeDeployToken(id: number): Promise<{
  deploy_token: string
  install_command: string
}> {
  const { data } = await apiClient.post<{ deploy_token: string; install_command: string }>(
    `/admin/nodes/${id}/deploy-token`,
  )
  return data
}
