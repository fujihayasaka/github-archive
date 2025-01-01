import type {SecurityCampaign} from '@github-ui/security-campaigns-shared/SecurityCampaign'
import type {User} from '@github-ui/security-campaigns-shared/types/user'

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
  indexPageEnabled: boolean
  campaignsGAEnabled: boolean
  draftCampaignsEnabled: boolean
  openOrgCampaignsCount: number | null
  maxCampaigns: number
}
