import type {SecurityCampaign} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import {calculateStatus} from './calculate-status'
import type {SecurityCampaignStatus} from '../types/security-campaign-status'

/**
 * Orders a list of open campaigns by due date and status.
 * Overdue campaigns are shown first, then open campaigns, then completed campaigns.
 * @param campaigns Open campaigns
 * @returns The ordered listed of open campaigns.
 */
export function orderOpenCampaignsList<T extends SecurityCampaign>(campaigns: T[]): T[] {
  return campaigns
    .map(campaign => ({
      ...campaign,
      status: calculateStatus(campaign),
    }))
    .sort((a, b) => {
      const statusComparison = campaignStatusPriority[a.status] - campaignStatusPriority[b.status]
      if (statusComparison !== 0) {
        return statusComparison
      }
      return new Date(a.endsAt).getTime() - new Date(b.endsAt).getTime()
    })
}

const campaignStatusPriority: Record<SecurityCampaignStatus, number> = {
  overdue: 1,
  open: 2,
  completed: 3,
  closed: 4,
  draft: 5,
}
