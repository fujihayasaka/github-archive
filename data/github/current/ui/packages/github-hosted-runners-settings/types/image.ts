import type {MachineSpecArchitecture} from './machine-spec'
import type {PlatformOsType} from './platform'

export const ImageSource = {
  Marketplace: 'Marketplace',
  Curated: 'Curated',
  Custom: 'Custom',
} as const

export type ImageSource = (typeof ImageSource)[keyof typeof ImageSource]

export const ImageDefinitionState = {
  Provisioning: 'Provisioning',
  Ready: 'Ready',
  Deleting: 'Deleting',
} as const

export type ImageDefinitionState = (typeof ImageDefinitionState)[keyof typeof ImageDefinitionState]

export const ImageVersionState = {
  Ready: 'Ready',
  ImportFailed: 'ImportFailed',
  ImportingBlob: 'ImportingBlob',
  ProvisioningImageVersion: 'ProvisioningImageVersion',
  Deleting: 'Deleting',
  Generating: 'Generating',
} as const

export type ImageVersionState = (typeof ImageVersionState)[keyof typeof ImageVersionState]

export type Image = {
  id: string | number
  displayName: string
  source: ImageSource
  osType: PlatformOsType
  architecture: MachineSpecArchitecture
  latestVersionSizeGb: number
  state?: ImageDefinitionState
  versionsCount?: number
  totalVersionsSize?: number
  latestVersion?: string
  imageVersions?: ImageVersion[]
  isImageGenerationSupported?: boolean
}

export type ImageVersion = {
  version: string
  state: ImageVersionState
  stateDetails?: string
  size?: number
  createdOn: string
  lastUsedOn?: string
}

export type ImageKey = {
  id: string | number
  source: ImageSource
  version: string
}
