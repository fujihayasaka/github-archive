import type {SecretRiskAssessmentPagePayload} from '../routes/SecretRiskAssessmentPage'
import type {Assessment} from '../types'

export function getSecretRiskAssessmentPageRoutePayload({
  hasAssessment = true,
  assessment = getAssessment(),
} = {}): SecretRiskAssessmentPagePayload {
  return {
    help_url: 'foo',
    org: {
      login: 'github',
    },
    assessment: hasAssessment ? assessment : undefined,
  }
}

export function getAssessment({
  can_request_another_assessment = false,
  is_complete = true,
  total_scans_wanted = 1,
  total_scans_completed = 0,
}: Partial<Assessment> = {}): Assessment {
  const nextRequestAt = new Date()
  nextRequestAt.setDate(nextRequestAt.getDate() + 90)
  const updatedAt = new Date()
  updatedAt.setDate(updatedAt.getDate() - 1)
  return {
    can_request_another_assessment,
    next_request_available_at: nextRequestAt.toISOString(),
    last_status_change: updatedAt.toISOString(),
    is_complete,
    total_scans_wanted,
    total_scans_completed,
    total_tokens_found: 0,
    total_tokens_found_in_public_repo: 0,
    total_tokens_found_push_protected_patterns: 0,
    total_tokens_found_non_provider_patterns: 0,
    tokens: [],
  }
}
