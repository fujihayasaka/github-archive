export type RunnerGroup = {
  id: string
  name: string
  allowPublic: boolean
  visibility: string
  selectedTargetsCount: number
}

export const ComputeService = {
  None: 'none',
  Actions: 'actions',
  Codespaces: 'codespaces',
} as const

export type ComputeService = (typeof ComputeService)[keyof typeof ComputeService]

export type NetworkSettingReferences = {
  id: string
}

export class NetworkConfiguration {
  id: string
  name: string
  createdOn: string
  computeService: ComputeService
  service: string
  runnerGroups: RunnerGroup[]
  networkSettingReferences: NetworkSettingReferences[]
  constructor(
    id: string,
    name: string,
    createdOn: string,
    computeService: ComputeService,
    service: string,
    runnerGroups: RunnerGroup[],
    networkSettingReferences: NetworkSettingReferences[],
  ) {
    this.id = id
    this.name = name
    this.createdOn = createdOn
    this.computeService = computeService
    this.service = service
    this.runnerGroups = runnerGroups
    this.networkSettingReferences = networkSettingReferences
  }
}
