export interface Assessment {
  can_request_another_assessment: boolean
  next_request_available_at: string
  last_status_change: string
  is_complete: boolean
  total_scans_wanted: number
  total_scans_completed: number
  total_tokens_found: number
  total_tokens_found_in_public_repo: number
  total_tokens_found_push_protected_patterns: number
  total_tokens_found_non_provider_patterns: number
  tokens: TokenTypeResult[]
}

export interface TokenTypeResult {
  id: string
  name: string
  unique_tokens_found_count: number
}
