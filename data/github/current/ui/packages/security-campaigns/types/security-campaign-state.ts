export type SecurityCampaignState = 'open' | 'closed' | 'draft'

export function parseSecurityCampaignState(v: string | null): SecurityCampaignState {
  if (v === 'open') {
    return 'open'
  }
  if (v === 'closed') {
    return 'closed'
  }
  if (v === 'draft') {
    return 'draft'
  }
  return 'open'
}
