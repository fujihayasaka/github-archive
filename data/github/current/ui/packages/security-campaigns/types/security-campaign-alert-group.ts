import type {Issue} from './issue'
import type {Repository} from './repository'

export type SecurityCampaignAlertGroup = {
  title: string
  repositories: string[]
  group: {
    kind: 'repository'
    repository: Repository
  } | null
  openCount: number
  closedCount: number
  openWithLinksCount: number
  // alertCount is the number of alerts that match the original filter supplied by the user. It is equal to either
  // openCount, closedCount, or openCount + closedCount, depending on whether is:open, is:closed, or is:open,closed
  // is supplied in the filter.
  alertCount?: number
  issue?: Issue
}
