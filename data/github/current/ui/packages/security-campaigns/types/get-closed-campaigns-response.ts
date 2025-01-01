import type {SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'

export interface GetClosedCampaignsResponse {
  campaigns: SecurityCampaignWithCounts[]
  nextCursor?: string
  prevCursor?: string
}
