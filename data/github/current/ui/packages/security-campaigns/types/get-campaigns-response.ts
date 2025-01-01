import type {SecurityCampaignWithCounts, SecurityCampaign} from './security-campaign'

export interface GetCampaignsResponse {
  campaigns: SecurityCampaignWithCounts[] | SecurityCampaign[]
  nextCursor?: string
  prevCursor?: string
}
