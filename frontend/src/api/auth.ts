import apiClient from './client'
import type { AuthResponse, LoginCredentials, User } from '@/types'

interface LoginApiResponse {
  token?: string
  token_type?: string
  two_factor?: boolean
  challenge?: string
  user?: {
    id: number
    name: string
    email: string
    is_admin: boolean
    roles: string[]
    two_factor_enabled?: boolean
  }
}

export type LoginResult =
  | { type: 'token'; token: string; user: User }
  | { type: 'two_factor'; challenge: string }

function mapUser(raw: NonNullable<LoginApiResponse['user']> | User): User {
  return {
    id: raw.id,
    name: raw.name,
    email: raw.email,
    is_admin: raw.is_admin,
    roles: raw.roles ?? [],
    locale: 'locale' in raw ? raw.locale : undefined,
    two_factor_enabled: 'two_factor_enabled' in raw ? !!raw.two_factor_enabled : undefined,
  }
}

export async function login(credentials: LoginCredentials): Promise<LoginResult> {
  const { data } = await apiClient.post<LoginApiResponse>('/auth/login', credentials)
  if (data.two_factor && data.challenge) {
    return { type: 'two_factor', challenge: data.challenge }
  }
  if (!data.token || !data.user) {
    throw new Error('Ungültige Login-Antwort')
  }
  return { type: 'token', token: data.token, user: mapUser(data.user) }
}

export async function twoFactorChallenge(challenge: string, code: string): Promise<AuthResponse> {
  const { data } = await apiClient.post<LoginApiResponse>('/auth/two-factor-challenge', {
    challenge,
    code,
  })
  if (!data.token || !data.user) {
    throw new Error('2FA fehlgeschlagen')
  }
  return { token: data.token, user: mapUser(data.user) }
}

export async function logout(): Promise<void> {
  await apiClient.post('/auth/logout')
}

export async function fetchCurrentUser(): Promise<User> {
  const { data } = await apiClient.get<User>('/auth/me')
  return mapUser(data)
}

export async function enableTwoFactor(): Promise<{
  secret: string
  otpauth_url: string
  recovery_codes: string[]
}> {
  const { data } = await apiClient.post('/auth/two-factor/enable')
  return data
}

export async function confirmTwoFactor(code: string): Promise<void> {
  await apiClient.post('/auth/two-factor/confirm', { code })
}

export async function disableTwoFactor(password: string): Promise<void> {
  await apiClient.post('/auth/two-factor/disable', { password })
}
