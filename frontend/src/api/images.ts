import apiClient from './client'
import type {
  CreateImageServerResponse,
  GameImage,
  ImageServer,
  ImageVersion,
  PaginatedResponse,
} from '@/types'

export async function fetchImageServers(page = 1): Promise<PaginatedResponse<ImageServer>> {
  const { data } = await apiClient.get<PaginatedResponse<ImageServer>>('/admin/image-servers', {
    params: { page },
  })
  return data
}

export async function createImageServer(payload: {
  name: string
  hostname?: string
  protocol?: 'sftp' | 'ftps' | 'ftp'
  port?: number
  base_path?: string
  username?: string
  password?: string
  public_url?: string
  is_active?: boolean
  mode?: 'deploy' | 'manual'
}): Promise<CreateImageServerResponse> {
  const { data } = await apiClient.post<CreateImageServerResponse>('/admin/image-servers', payload)
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

export async function regenerateImageServerDeployToken(id: number): Promise<{
  deploy_token: string
  install_command: string
}> {
  const { data } = await apiClient.post<{ deploy_token: string; install_command: string }>(
    `/admin/image-servers/${id}/deploy-token`,
  )
  return data
}

export async function fetchImages(page = 1): Promise<PaginatedResponse<GameImage>> {
  const { data } = await apiClient.get<PaginatedResponse<GameImage>>('/admin/images', {
    params: { page },
  })
  return data
}

export async function createImage(payload: {
  name: string
  slug?: string
  description?: string
  game_template_id?: number | null
}): Promise<GameImage> {
  const { data } = await apiClient.post<GameImage>('/admin/images', payload)
  return data
}

export async function registerImage(payload: {
  slug: string
  version: string
  name?: string
  description?: string
  game_template_id?: number | null
  checksum_sha256: string
  size_bytes?: number
  is_latest?: boolean
}): Promise<{ image: GameImage; version: ImageVersion }> {
  const { data } = await apiClient.post<{ image: GameImage; version: ImageVersion }>(
    '/admin/images/register',
    payload,
  )
  return data
}
