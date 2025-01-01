import type {SecurityCampaign, SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'

export interface GetCampaignsResponse {
  campaigns: SecurityCampaignWithCounts[] | SecurityCampaign[]
  nextCursor?: string
  prevCursor?: string
}
