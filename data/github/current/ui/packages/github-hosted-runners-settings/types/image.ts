import type {MachineSpecArchitecture} from './machine-spec'
import type {PlatformOsType} from './platform'

export enum ImageSource {
  Marketplace = 'Marketplace',
  Curated = 'Curated',
  Custom = 'Custom',
}

export enum ImageDefinitionState {
  Provisioning = 'Provisioning',
  Ready = 'Ready',
  Deleting = 'Deleting',
}

export enum ImageVersionState {
  Ready = 'Ready',
  ImportFailed = 'ImportFailed',
  ImportingBlob = 'ImportingBlob',
  ProvisioningImageVersion = 'ProvisioningImageVersion',
  Deleting = 'Deleting',
  Generating = 'Generating',
}

export type Image = {
  id: string | number
  displayName: string
  source: ImageSource
  osType: PlatformOsType
  architecture: MachineSpecArchitecture
  sizeGb: number
  state?: ImageDefinitionState
  versionCount?: number
  totalVersionsSize?: number
  latestVersion?: string
  imageVersions?: ImageVersion[]
  isImageGenerationSupported?: boolean
}

export type ImageVersion = {
  version: string
  state: ImageVersionState
  failureReason?: string
  size?: number
  createdOn: string
  lastUsedOn?: string
}
