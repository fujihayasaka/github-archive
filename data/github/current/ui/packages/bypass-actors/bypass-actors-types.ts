export type BypassActor = {
  id?: number
  _id?: number
  actorId: number | string | null
  actorType: BypassActorType
  name: string
  _enabled: boolean
  _dirty: boolean
  bypassMode: ActorBypassMode
  owner?: string
}

export type BypassActorType =
  | 'RepositoryRole'
  | 'Team'
  | 'Integration'
  | 'OrganizationAdmin'
  | 'DeployKey'
  | 'EnterpriseTeam'
  | 'EnterpriseOwner'

export const ActorBypassMode = {
  ALWAYS: 0,
  PRS_ONLY: 1,
} as const

export type ActorBypassMode = (typeof ActorBypassMode)[keyof typeof ActorBypassMode]
