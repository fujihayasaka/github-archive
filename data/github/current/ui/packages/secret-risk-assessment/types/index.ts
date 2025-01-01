export interface Assessment {
  can_request_another_assessment: boolean
  next_request_available_at: string
  requested_at: string
  last_status_change: string
  is_complete: boolean
  total_scans_wanted: number
  total_scans_completed: number
  total_tokens_found: number
  total_tokens_found_in_public_repo: number
  total_tokens_found_push_protected_patterns: number
  total_tokens_found_non_provider_patterns: number
  total_repositories_with_results: number
  distinct_repos_scanned: number
  tokens: TokenTypeResult[]
}

export interface TokenTypeResult {
  id: string
  name: string
  distinct_repos_count: number
  unique_tokens_found_count: number
}

export interface TokenTypeLocaleResult {
  id: string
  name: string
  distinct_repos_count: string
  unique_tokens_found_count: string
}

export interface Cost {
  increased_license_usage: number
  per_license: string
  total: string
}
