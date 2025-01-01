import {calculateDaysLeft} from '../calculate-days-left'
import {getSecurityCampaignWithCounts} from '@github-ui/security-campaigns-shared/test-utils/mock-data'
import {calculateStatus} from '../calculate-status'

jest.mock('../../utils/calculate-days-left')

describe('calculateStatus', () => {
  const mockCalculateDaysLeft = calculateDaysLeft as jest.Mock
  const campaign = getSecurityCampaignWithCounts()

  it('should return "closed" if closedAt is present', () => {
    const status = calculateStatus({
      ...campaign,
      closedAt: new Date().toISOString(),
      endsAt: new Date().toISOString(),
      openCount: 1,
    })

    expect(status).toBe('closed')
  })

  it('should return "completed" if openCount is 0', () => {
    const status = calculateStatus({
      ...campaign,
      closedAt: null,
      endsAt: new Date().toISOString(),
      openCount: 0,
    })

    expect(status).toBe('completed')
  })

  it('should return "overdue" if it ends in the past', () => {
    mockCalculateDaysLeft.mockReturnValue(-1)
    const status = calculateStatus({
      ...campaign,
      closedAt: null,
      endsAt: new Date().toISOString(),
      openCount: 1,
    })

    expect(status).toBe('overdue')
  })

  it('should return "open" if none of the other conditions are met', () => {
    mockCalculateDaysLeft.mockReturnValue(1)
    const status = calculateStatus({
      ...campaign,
      closedAt: null,
      endsAt: new Date().toISOString(),
      openCount: 1,
    })

    expect(status).toBe('open')
  })

  it('should return "draft" if publishedAt is not present', () => {
    const status = calculateStatus({
      ...campaign,
      closedAt: null,
      endsAt: new Date().toISOString(),
      openCount: 1,
      publishedAt: null,
    })

    expect(status).toBe('draft')
  })
})
