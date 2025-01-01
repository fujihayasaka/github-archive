export type User = {
  displayLogin: string
  id: number
  profileName: string
  avatarUrl: string
}

export type Organization = {
  id: number
  name: string
  avatarUrl: string
  description: string | null
}

export type EnterpriseTeam = {
  id: number
  name: string
  slug: string
  description: string
  totalMemberCount: number
  totalOrganizationCount: number
  totalRoleCount: number
}
