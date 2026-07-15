import apiClient from './client'
import type { PanelJob } from '@/types'

export async function fetchJob(uuid: string): Promise<PanelJob & { result?: Record<string, unknown> }> {
  const { data } = await apiClient.get<{ job: PanelJob & { result?: Record<string, unknown> } }>(
    `/client/jobs/${uuid}`,
  )
  return data.job
}

export async function pollJob(
  uuid: string,
  options: { intervalMs?: number; timeoutMs?: number } = {},
): Promise<PanelJob & { result?: Record<string, unknown> }> {
  const intervalMs = options.intervalMs ?? 800
  const timeoutMs = options.timeoutMs ?? 120_000
  const started = Date.now()

  while (Date.now() - started < timeoutMs) {
    const job = await fetchJob(uuid)
    if (job.status === 'completed' || job.status === 'failed') {
      return job
    }
    await new Promise((r) => setTimeout(r, intervalMs))
  }

  throw new Error('Job-Timeout — Agent antwortet nicht')
}
