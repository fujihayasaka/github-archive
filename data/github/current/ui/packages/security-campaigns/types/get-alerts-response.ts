import type {SecurityCampaignAlert} from './security-campaign-alert'

export interface GetAlertsResponse {
  alerts: SecurityCampaignAlert[]
  alertCount: number
  openCount: number
  closedCount: number
  openWithLinksCount: number
  nextCursor: string
  prevCursor: string
}
