import apiClient from './client'
import type { GameImage, ImageServer, PaginatedResponse } from '@/types'

export async function fetchImageServers(page = 1): Promise<PaginatedResponse<ImageServer>> {
  const { data } = await apiClient.get<PaginatedResponse<ImageServer>>('/admin/image-servers', {
    params: { page },
  })
  return data
}

export async function createImageServer(payload: {
  name: string
  hostname: string
  protocol: 'sftp' | 'ftps' | 'ftp'
  port: number
  base_path: string
  username: string
  password?: string
  public_url?: string
  is_active?: boolean
}): Promise<ImageServer> {
  const { data } = await apiClient.post<ImageServer>('/admin/image-servers', payload)
  return data
}

export async function updateImageServer(
  id: number,
  payload: Partial<ImageServer & { password?: string }>,
): Promise<ImageServer> {
  const { data } = await apiClient.put<ImageServer>(`/admin/image-servers/${id}`, payload)
  return data
}

export async function deleteImageServer(id: number): Promise<void> {
  await apiClient.delete(`/admin/image-servers/${id}`)
}

export async function fetchImages(page = 1): Promise<PaginatedResponse<GameImage>> {
  const { data } = await apiClient.get<PaginatedResponse<GameImage>>('/admin/images', {
    params: { page },
  })
  return data
}
