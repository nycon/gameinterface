export type UserRole = 'admin' | 'client'

export interface User {
  id: number
  name: string
  email: string
  is_admin: boolean
  roles: string[]
  locale?: string
  created_at?: string
  two_factor_enabled?: boolean
  reseller_id?: number | null
}

export function isUserAdmin(user: User | null | undefined): boolean {
  if (!user) return false
  return user.is_admin || user.roles.includes('admin')
}

export function userDisplayRole(user: User): UserRole {
  return isUserAdmin(user) ? 'admin' : 'client'
}

export type ServerStatus =
  | 'installing'
  | 'offline'
  | 'starting'
  | 'online'
  | 'stopping'
  | 'deleting'
  | 'error'

export interface ServerOwner {
  id: number
  name: string
  email?: string
}

export interface ServerNode {
  id: number
  name: string
}

export interface ServerTemplate {
  id: number
  name: string
  slug?: string
}

export interface ServerAllocation {
  id: number
  ip: string
  port: number
  protocol?: string
}

export interface Server {
  id: number
  uuid: string
  name: string
  status: ServerStatus
  user_id: number
  node_id: number
  linux_user?: string
  memory_max?: string
  cpu_quota?: string
  owner?: ServerOwner
  node?: ServerNode
  template?: ServerTemplate
  allocations?: ServerAllocation[]
  created_at?: string
}

export function serverGameName(server: Server): string {
  return server.template?.name ?? '—'
}

export function serverNodeName(server: Server): string {
  return server.node?.name ?? '—'
}

export function serverOwnerName(server: Server): string {
  return server.owner?.name ?? '—'
}

export function serverPort(server: Server): string | number {
  return server.allocations?.[0]?.port ?? '—'
}

export function serverMemoryDisplay(server: Server): string {
  return server.memory_max ?? '—'
}

export function isServerOnline(status: ServerStatus): boolean {
  return status === 'online' || status === 'starting'
}

export function isServerStopped(status: ServerStatus): boolean {
  return status === 'offline' || status === 'error' || status === 'installing'
}

export type NodeStatus = 'online' | 'offline' | 'maintenance'

export interface Node {
  id: number
  uuid: string
  name: string
  hostname: string
  ip_address: string
  status: NodeStatus
  cpu_cores?: number
  memory_mb?: number
  disk_gb?: number
  phpmyadmin_url?: string | null
  last_heartbeat_at?: string
  servers_count?: number
  allocations_count?: number
}

export interface CreateNodeResponse {
  node: Node
  token?: string
  deploy_token: string
  install_command: string
}

export interface ImageServer {
  id: number
  name: string
  hostname: string
  protocol: 'sftp' | 'ftps' | 'ftp'
  port: number
  base_path: string
  username: string
  public_url?: string | null
  is_active: boolean
  status?: 'pending' | 'ready' | 'error'
}

export interface CreateImageServerResponse {
  image_server: ImageServer
  deploy_token?: string
  install_command?: string
}

export interface ImageVersion {
  id: number
  version: string
  size_bytes?: number
  is_latest?: boolean
}

export interface GameImage {
  id: number
  name: string
  slug: string
  description?: string
  template?: ServerTemplate
  versions?: ImageVersion[]
}

export interface Template {
  id: number
  name: string
  slug: string
  type: 'steam' | 'minecraft' | 'url' | 'custom'
  yaml_definition: string
  steam_app_id?: string | null
  is_active: boolean
}

export interface PanelJob {
  id: number
  uuid: string
  type: string
  status: 'pending' | 'running' | 'completed' | 'failed'
  progress?: number
  error?: string | null
  result?: Record<string, unknown>
  created_at: string
  node?: ServerNode
  server?: { id: number; name: string }
}

export interface AuditLogUser {
  id: number
  name: string
  email?: string
}

export interface AuditLog {
  id: number
  action: string
  user?: AuditLogUser
  ip_address: string
  created_at: string
}

export interface Setting {
  id?: number
  key: string
  value: string | null
}

export interface Backup {
  id: number
  uuid: string
  name: string
  size_bytes: number
  status?: string
  created_at: string
}

export interface FileNode {
  name: string
  path: string
  type: 'file' | 'directory'
  size?: number
  modified_at?: string
  children?: FileNode[]
}

export interface DashboardStats {
  users: number
  nodes: number
  nodes_online: number
  servers: number
  servers_online: number
  jobs_pending: number
  jobs_running: number
}

export interface DashboardResponse {
  stats: DashboardStats
  recent_servers: Server[]
  recent_jobs: PanelJob[]
}

export interface LoginCredentials {
  email: string
  password: string
}

export interface AuthResponse {
  token: string
  user: User
}

export interface ApiError {
  message: string
  errors?: Record<string, string[]>
}

export interface PaginatedResponse<T> {
  data: T[]
  current_page: number
  last_page: number
  per_page: number
  total: number
}

export type StatusBadgeValue =
  | ServerStatus
  | NodeStatus
  | 'maintenance'
  | 'pending'
  | 'running'
  | 'completed'
  | 'failed'
  | 'stopped'
  | string
