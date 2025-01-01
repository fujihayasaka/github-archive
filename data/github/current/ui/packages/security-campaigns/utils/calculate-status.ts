import {calculateDaysLeft} from './calculate-days-left'
import type {SecurityCampaignStatus} from '../types/security-campaign-status'
import {isCampaignWithCounts} from './is-campaign-with-counts'
import type {SecurityCampaign, SecurityCampaignWithCounts} from '../types/security-campaign'

export function calculateStatus(campaign: SecurityCampaignWithCounts | SecurityCampaign): SecurityCampaignStatus {
  const {closedAt, endsAt, publishedAt} = campaign
  if (!publishedAt) {
    return 'draft' as const
  }

  const isCompleted = isCampaignWithCounts(campaign) && campaign.openCount === 0

  const daysLeft = calculateDaysLeft(new Date(endsAt))
  const isOverdue = daysLeft < 0

  if (closedAt) {
    return 'closed' as const
  }

  if (isCompleted) {
    return 'completed' as const
  }

  if (isOverdue) {
    return 'overdue' as const
  }

  return 'open' as const
}
