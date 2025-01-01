export type User = {
  displayLogin: string
  id: number
  profileName: string
  avatarUrl: string
}

export type Organization = {
  id: number
  name?: string
  login: string
  avatarUrl: string
  description: string | null
}

export type ExternalGroup = {
  id: number
  displayName: string
  updatedAt: string
}

export type EnterpriseTeam = {
  id: number
  name: string
  slug: string
  description: string
  totalMemberCount: number
  totalOrganizationCount: number
  totalRoleCount: number
  organizationSelectionType: string
  linkedToExternalGroup: boolean
}
