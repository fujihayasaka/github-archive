import type {User} from './user'
import type {Team} from './team'

export type SecurityCampaignForm = {
  name: string
  description: string
  endsAt: string
  managers: User[]
  teamManagers: Team[]
  contactLink: string | null
  generateAutofixPullRequests?: boolean
  generateIssues?: boolean
}

export type SecurityCampaign = SecurityCampaignForm & {
  id: number
  number: number
  createdAt: string
  closedAt: string | null
  managers: User[]
  teamManagers: Team[]
  creationQuery: string | null
  publishedAt: string | null
}

export type DraftSecurityCampaign = Omit<SecurityCampaign, 'description' | 'endsAt' | 'publishedAt'> & {
  description: string | null
  endsAt: string | null
  creationQuery: string
  publishedAt: null
}

export type SecurityCampaignWithCounts = SecurityCampaign & {
  openCount: number
  closedCount: number
  openWithLinksCount: number
}
