import type {User} from './user'

export type SecurityCampaignForm = {
  name: string
  description: string
  endsAt: string
  manager: User | null
  generateAutofixPullRequests?: boolean
}

export type SecurityCampaign = SecurityCampaignForm & {
  id: number
  number: number
  createdAt: string
  closedAt: string | null
  showPath: string
  updatePath: string
  deletePath: string
  closePath: string
  reopenPath: string
}

export type SecurityCampaignWithCounts = SecurityCampaign & {
  openCount: number
  closedCount: number
  openWithLinksCount: number
}
