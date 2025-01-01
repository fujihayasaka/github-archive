import {setupServer} from 'msw/node'
import {http, HttpResponse} from 'msw'

import type {SecretRiskAssessmentPagePayload} from '../routes/SecretRiskAssessmentPage'
import type {Assessment, Cost} from '../types'
import {initialAssessment} from '../api'

export const mockServer = setupServer(
  http.get('/orgs/:org/security/assessments/json', _info => {
    return HttpResponse.json(initialAssessment(), {status: 200})
  }),
  http.post('/orgs/:org/security/assessments', _info => {
    return HttpResponse.json(null, {status: 200})
  }),
)

export function getSecretRiskAssessmentPageRoutePayload({
  hasAssessment = true,
  assessment = getAssessment(),
  isEnterpriseOrMT = false,
  showEnableSecretProtectionButton = true,
} = {}): SecretRiskAssessmentPagePayload {
  return {
    help_url: 'foo',
    org: {
      login: 'github',
    },
    assessment: hasAssessment ? assessment : null,
    cost: getCost(),
    can_skip_rescan: false,
    is_enterprise_or_mt: isEnterpriseOrMT,
    show_enable_secret_protection_button: showEnableSecretProtectionButton,
  }
}

export function getAssessment({
  can_request_another_assessment = false,
  is_complete = true,
  total_scans_wanted = 1,
  total_scans_completed = 1,
  total_tokens_found = 1,
  next_request_available_at = undefined,
}: Partial<Assessment> = {}): Assessment {
  const nextRequestAt = new Date()
  nextRequestAt.setDate(nextRequestAt.getDate() + 90)
  const updatedAt = new Date()
  updatedAt.setDate(updatedAt.getDate() - 1)
  return {
    can_request_another_assessment,
    next_request_available_at: next_request_available_at ? next_request_available_at : nextRequestAt.toISOString(),
    requested_at: updatedAt.toISOString(),
    last_status_change: updatedAt.toISOString(),
    is_complete,
    total_scans_wanted,
    total_scans_completed,
    total_tokens_found,
    total_tokens_found_in_public_repo: 0,
    total_tokens_found_push_protected_patterns: 0,
    total_tokens_found_non_provider_patterns: 0,
    total_repositories_with_results: 0,
    distinct_repos_scanned: 0,
    tokens: [],
  }
}

export function getCost(): Cost {
  return {
    total: '$0',
    per_license: '$0',
    increased_license_usage: 0,
  }
}
