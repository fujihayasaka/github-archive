export type ImageDefinition = {
  id: number
  name: string
  osType: OsType
  architecture: Architecture
  enabled: boolean
  featureFlag: string
  pointsToImageDefinitionId: number
  createdAt: string
  updatedAt: string
  imageVersionsCount: number
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
}

export type OsType = 'Windows' | 'Linux'

export type Architecture = 'X64' | 'Arm64'

export type ImageVersionState = 'Pending' | 'Provisioning' | 'Ready' | 'ProvisionFailed' | 'Deleting'

export type ImageDefinitionEnabled = 'Enabled' | 'Disabled' | 'FeatureFlag'

export type CreateCuratedImagePointerPayload = {
  name: string
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
  osType: string
  architecture: string
  enabled: boolean
  featureFlag: string
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
