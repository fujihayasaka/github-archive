export type ActorRoleAssignment = {
  actor: Actor
  role_assignments: RoleAssignment[]
}

export type RoleAssignment = {
  role: Role
  directly_assigned: boolean
  indirect_assignments: IndirectRoleAssignmentSource[]
}

export type Role = {
  id: number
  name: string
  description: string | null
  octicon: string
}

export type IndirectRoleAssignmentSource = {
  team_name: string
  team_url: string
  type: string
}

export type Actor = {
  id: number
  name: string
  description: string | null
  avatar_url: string
  type: ActorType
}

export const ActorType = {
  User: 'User',
  EnterpriseTeam: 'BusinessTeam',
  Team: 'Team',
} as const

export type ActorType = (typeof ActorType)[keyof typeof ActorType]

export type ActorBasicMeta = {
  id: number
  name: string
  type: ActorType
}
