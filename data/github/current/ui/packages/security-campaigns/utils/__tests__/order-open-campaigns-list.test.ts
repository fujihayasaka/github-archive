import {orderOpenCampaignsList} from '../order-open-campaigns-list'
import {calculateStatus} from '../calculate-status'
import type {SecurityCampaignStatus} from '../../types/security-campaign-status'
import {getRelativeDate} from '../../test-utils/get-relative-date'
import {getSecurityCampaignWithCounts} from '../../test-utils/mock-data'
import type {SecurityCampaignWithCounts} from '../../types/security-campaign'

jest.mock('../calculate-status')

describe('orderOpenCampaignsList', () => {
  const mockCalculateStatus = calculateStatus as jest.Mock

  const campaignsMap = new Map<SecurityCampaignWithCounts, SecurityCampaignStatus>([
    [{...getSecurityCampaignWithCounts(), id: 8, endsAt: getRelativeDate(3).toISOString()}, 'completed'],
    [{...getSecurityCampaignWithCounts(), id: 1, endsAt: getRelativeDate(-10).toISOString()}, 'overdue'],
    [{...getSecurityCampaignWithCounts(), id: 9, endsAt: getRelativeDate(5).toISOString()}, 'completed'],
    [{...getSecurityCampaignWithCounts(), id: 3, endsAt: getRelativeDate(-3).toISOString()}, 'overdue'],
    [{...getSecurityCampaignWithCounts(), id: 6, endsAt: getRelativeDate(10).toISOString()}, 'open'],
    [{...getSecurityCampaignWithCounts(), id: 4, endsAt: getRelativeDate(3).toISOString()}, 'open'],
    [{...getSecurityCampaignWithCounts(), id: 7, endsAt: getRelativeDate(-10).toISOString()}, 'completed'],
    [{...getSecurityCampaignWithCounts(), id: 2, endsAt: getRelativeDate(-5).toISOString()}, 'overdue'],
    [{...getSecurityCampaignWithCounts(), id: 5, endsAt: getRelativeDate(5).toISOString()}, 'open'],
  ])

  const campaigns = Array.from(campaignsMap.keys())

  beforeEach(() => {
    // Mock the calculateStatus function to return the status for each campaign
    for (const [_, status] of campaignsMap) {
      mockCalculateStatus.mockReturnValueOnce(status)
    }
  })

  it('should order campaigns by due date and status', () => {
    const orderedCampaigns = orderOpenCampaignsList(campaigns)
    const orderedIds = orderedCampaigns.map(campaign => campaign.id)
    expect(orderedIds).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9])

    expect(calculateStatus).toHaveBeenCalledTimes(9)
  })
})
