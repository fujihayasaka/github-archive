import type {FgpMetadata} from '@github-ui/role-assignments/types/fgp-metadata'

// Payloads
export interface NewEnterpriseRoleAssignmentPayload {
  slug: string
  enterpriseName: string
  enterpriseOrgs: EnterpriseOrg[]
  enterpriseTeamOrgAssignmentLimitExceeded: boolean
  roles: Role[]
}

// Enterprise
export interface EnterpriseOrg {
  id: number
  displayLogin: string
  avatarURL: string
}

// Roles
export interface Role {
  id: number
  name: string
  description: string | null
  icon: string
  fgpMetadata: FgpMetadata
  enterpriseOwner?: {
    slug: string
    name: string
  }
}

export interface RoleStatus {
  status: 'enabled' | 'disabled'
  statusText?: string
}

// Assignments
export type AssigneeType = 'user' | 'businessteam' | 'team'
