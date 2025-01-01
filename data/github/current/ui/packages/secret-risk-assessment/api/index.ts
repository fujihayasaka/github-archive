import {queryOptions, useMutation, useQueryClient} from '@github-ui/react-query'
import {reactFetchJSON} from '@github-ui/verified-fetch'

import {riskAssessmentJsonPath, riskAssessmentPath} from '../paths'
import type {Assessment} from '../types'

export function initialAssessment(): Assessment {
  const now = new Date()
  const nextAvailableAt = new Date()
  nextAvailableAt.setDate(nextAvailableAt.getDate() + 90)
  return {
    can_request_another_assessment: false,
    next_request_available_at: nextAvailableAt.toISOString(),
    requested_at: now.toISOString(),
    last_status_change: now.toISOString(),
    is_complete: false,
    total_scans_wanted: 1,
    total_scans_completed: 0,
    total_tokens_found: 0,
    total_tokens_found_in_public_repo: 0,
    total_tokens_found_push_protected_patterns: 0,
    total_tokens_found_non_provider_patterns: 0,
    total_repositories_with_results: 0,
    distinct_repos_scanned: 0,
    tokens: [],
  }
}

export const queries = {
  assessment: (org: string) =>
    queryOptions({
      queryKey: ['secret-scanning', 'assessment', org] as const,
      // Return type is nullable to allow `initialData` to be set to null
      queryFn: async ({queryKey: [, , orgLogin]}): Promise<Assessment | null> => {
        const res = await reactFetchJSON(riskAssessmentJsonPath(orgLogin))
        if (!res.ok) {
          throw new Error('Failed to fetch assessment')
        }
        const newAssessment = (await res.json()) as Assessment | null
        if (!newAssessment) {
          throw new Error('Assessment not found')
        }
        return newAssessment
      },
    }),
}

export function useCreateAssessmentMutation({org}: {org: string}) {
  const client = useQueryClient()
  return useMutation({
    mutationFn: async () => {
      const res = await reactFetchJSON(riskAssessmentPath(org), {method: 'POST'})
      if (!res.ok) {
        throw new Error(`Failed to start assessment, status: ${res.status}`)
      }
    },
    onSuccess: () => {
      client.setQueryData(queries.assessment(org).queryKey, initialAssessment())
    },
  })
}
