export type ImageDefinition = {
  id: number
  name: string
  ownerId: OwnerId
  osType: OsType
  architecture: Architecture
  enabled: boolean
  featureFlag: string
  pointsToImageDefinitionId: number
  createdAt: string
  updatedAt: string
  imageVersionsCount: number
  latestVersion: string
  isImageGenerationSupported: boolean
}

export type ImageVersion = {
  id: number
  imageDefinitionId: number
  version: string
  state: ImageVersionState
  stateDetails: string
  sizeGb: number
  enabled: boolean
  createdAt: string
  updatedAt: string
  resourceId: string
  vmGeneration: VMGeneration
  osState: OsState
  azurePurchasePlan: string
  agentUser: string
}

export type OwnerId = 'github' | 'partner' | 'azuredevops'

export type OsType = 'Windows' | 'Linux' | 'MacOS'

export type Architecture = 'X64' | 'Arm64'

export type VMGeneration = 'Gen1' | 'Gen2'

export type OsState = 'Generalized' | 'Specialized'

export type ImageVersionState = 'Pending' | 'Provisioning' | 'Ready' | 'ProvisionFailed' | 'Deleting'

export type ImageDefinitionEnabled = 'Enabled' | 'Disabled' | 'FeatureFlag'

export type CreateCuratedImagePointerPayload = {
  name: string
  ownerId: OwnerId
  pointsToImageDefinitionId: number | undefined
  enabled: boolean
  featureFlag: string
}

export type UpdateCuratedImagePointerPayload = {
  id: number
  name: string
  pointsToImageDefinitionId: number | undefined
  enabled: boolean
  featureFlag: string
}

export type CreateCuratedImagePayload = {
  name: string
  ownerId: OwnerId
  osType: string
  architecture: string
  enabled: boolean
  featureFlag: string
  isImageGenerationSupported: boolean
}

export type UpdateCuratedImagePayload = {
  id: number
  name: string
  osType: string
  architecture: string
  enabled: boolean
  featureFlag: string
}

export type UpdateCuratedImageVersionPayload = {
  id: number
  version: string
  enabled: boolean
}

export type DeleteCuratedImagePayload = {
  id: number
}

export type DeleteCuratedImageVersionPayload = {
  id: number
  version: string
}
