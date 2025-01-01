import type {SecurityCampaign, SecurityCampaignWithCounts} from '../types/security-campaign'

export const isCampaignWithCounts = (
  campaign: SecurityCampaign | SecurityCampaignWithCounts,
): campaign is SecurityCampaignWithCounts => {
  return 'openCount' in campaign && 'closedCount' in campaign && 'openWithLinksCount' in campaign
}
