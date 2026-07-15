import axios, { type AxiosError, type InternalAxiosRequestConfig } from 'axios'
import type { ApiError } from '@/types'

const apiClient = axios.create({
  baseURL: '/api',
  headers: {
    Accept: 'application/json',
    'Content-Type': 'application/json',
  },
})

apiClient.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const token = localStorage.getItem('auth_token')
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

apiClient.interceptors.response.use(
  (response) => response,
  (error: AxiosError<ApiError>) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('auth_token')
      localStorage.removeItem('auth_user')
      if (!window.location.pathname.startsWith('/login')) {
        window.location.href = '/login'
      }
    }
    return Promise.reject(error)
  },
)

export default apiClient

export function getErrorMessage(error: unknown, fallback = 'Ein Fehler ist aufgetreten'): string {
  if (axios.isAxiosError<ApiError>(error)) {
    return error.response?.data?.message ?? fallback
  }
  if (error instanceof Error) {
    return error.message
  }
  return fallback
}
