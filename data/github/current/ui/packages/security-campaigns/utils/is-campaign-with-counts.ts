import type {SecurityCampaign, SecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/SecurityCampaign'

export const isCampaignWithCounts = (
  campaign: SecurityCampaign | SecurityCampaignWithCounts,
): campaign is SecurityCampaignWithCounts => {
  return 'openCount' in campaign && 'closedCount' in campaign && 'openWithLinksCount' in campaign
}
