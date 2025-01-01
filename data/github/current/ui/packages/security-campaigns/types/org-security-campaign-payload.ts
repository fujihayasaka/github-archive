import type {SecurityCampaign} from './security-campaign'
import type {User} from './user'

export type OrgSecurityCampaignPayload = {
  campaign: SecurityCampaign
  organizationLogin: string
  currentUser: User
  orgLevelView: boolean
  customPropertyNames: string[]
  maxManagers: number
  maxAlerts: number
  orgId: number
  showNewAutofixFilters: boolean
  showCampaignManagementActions: boolean
  showIncompleteDataWarning: boolean
  incompleteDataWarningDocHref: string
  showLimitedAlertsWarning: boolean
  indexPageEnabled: boolean
  openOrgCampaignsCount: number | null
  maxCampaigns: number
  bestPracticeCampaignsDocsUrl: string
  hasOpenSpam: boolean
}
