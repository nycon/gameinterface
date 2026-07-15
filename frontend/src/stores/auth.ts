import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import * as authApi from '@/api/auth'
import { getErrorMessage } from '@/api/client'
import type { LoginCredentials, User } from '@/types'
import { isUserAdmin } from '@/types'

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(loadStoredUser())
  const token = ref<string | null>(localStorage.getItem('auth_token'))
  const loading = ref(false)
  const error = ref<string | null>(null)
  const pendingChallenge = ref<string | null>(null)

  const isAuthenticated = computed(() => !!token.value && !!user.value)
  const isAdmin = computed(() => isUserAdmin(user.value))
  const isReseller = computed(
    () => !!user.value && (user.value.roles.includes('reseller') || isUserAdmin(user.value)),
  )

  function loadStoredUser(): User | null {
    const raw = localStorage.getItem('auth_user')
    if (!raw) return null
    try {
      const parsed = JSON.parse(raw) as User
      return {
        ...parsed,
        is_admin: parsed.is_admin ?? false,
        roles: parsed.roles ?? [],
      }
    } catch {
      return null
    }
  }

  function persistSession(newToken: string, newUser: User) {
    token.value = newToken
    user.value = newUser
    pendingChallenge.value = null
    localStorage.setItem('auth_token', newToken)
    localStorage.setItem('auth_user', JSON.stringify(newUser))
  }

  function clearSession() {
    token.value = null
    user.value = null
    pendingChallenge.value = null
    localStorage.removeItem('auth_token')
    localStorage.removeItem('auth_user')
  }

  async function login(credentials: LoginCredentials) {
    loading.value = true
    error.value = null
    try {
      const result = await authApi.login(credentials)
      if (result.type === 'two_factor') {
        pendingChallenge.value = result.challenge
        return { twoFactor: true as const }
      }
      persistSession(result.token, result.user)
      return { twoFactor: false as const, user: result.user }
    } catch (err) {
      error.value = getErrorMessage(err, 'Anmeldung fehlgeschlagen')
      throw err
    } finally {
      loading.value = false
    }
  }

  async function completeTwoFactor(code: string) {
    if (!pendingChallenge.value) throw new Error('Kein 2FA-Challenge')
    loading.value = true
    error.value = null
    try {
      const response = await authApi.twoFactorChallenge(pendingChallenge.value, code)
      persistSession(response.token, response.user)
      return response.user
    } catch (err) {
      error.value = getErrorMessage(err, '2FA fehlgeschlagen')
      throw err
    } finally {
      loading.value = false
    }
  }

  async function logout() {
    try {
      await authApi.logout()
    } catch {
      // Session trotzdem lokal beenden
    } finally {
      clearSession()
    }
  }

  async function fetchUser() {
    if (!token.value) return null
    try {
      const currentUser = await authApi.fetchCurrentUser()
      user.value = currentUser
      localStorage.setItem('auth_user', JSON.stringify(currentUser))
      return currentUser
    } catch {
      clearSession()
      return null
    }
  }

  return {
    user,
    token,
    loading,
    error,
    pendingChallenge,
    isAuthenticated,
    isAdmin,
    isReseller,
    login,
    completeTwoFactor,
    logout,
    fetchUser,
    clearSession,
  }
})
