import type {SecurityCampaignWithCounts} from './security-campaign'

export interface GetClosedCampaignsResponse {
  campaigns: SecurityCampaignWithCounts[]
  nextCursor?: string
  prevCursor?: string
}
