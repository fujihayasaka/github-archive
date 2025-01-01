import type {NewRunnerPayload} from '../routes/NewRunner'
import type {EditRunnerPayload} from '../routes/EditRunner'
import {RunnerGroupVisibility, type RunnerCreateForm, type RunnerEditForm, type RunnerGroup} from '../types/runner'
import {ImageSource, ImageVersionState} from '../types/image'
import {PlatformOsType, type PlatformId} from '../types/platform'
import {type MachineSpec, MachineSpecArchitecture} from '../types/machine-spec'
import type {Image, ImageKey, ImageVersion} from '../types/image'

const defaultGroup: RunnerGroup = {
  id: 1,
  name: 'Default',
  visibility: RunnerGroupVisibility.All,
  allowPublic: false,
  selectedTargets: [],
  precreated: true,
}
const anotherGroup: RunnerGroup = {
  id: 2,
  name: 'Another Group',
  visibility: RunnerGroupVisibility.All,
  allowPublic: false,
  selectedTargets: [],
  precreated: true,
}

const defaultMachineSpec = {
  id: '4-core',
  architecture: MachineSpecArchitecture.x64,
  storageGb: 100,
  memoryGb: 16,
  cpuCores: 4,
  type: 'basic',
  documentationUrl: '',
  gpu: null,
} as const satisfies MachineSpec

const githubLinuxImage = {
  id: 'ubuntu-latest',
  displayName: 'Latest (22.04)',
  source: ImageSource.Curated,
  osType: PlatformOsType.Linux,
  architecture: MachineSpecArchitecture.x64,
  latestVersionSizeGb: 86,
} as const satisfies Image

const customImageVersion = {
  version: '1.0.0',
  state: ImageVersionState.Ready,
  size: 300,
  createdOn: '',
} as const satisfies ImageVersion

export function getNewRunnerRoutePayload(input?: {
  isPublicIpAllowed?: boolean
  runnerGroups?: RunnerGroup[]
  maxConcurrentJobsDefault?: number
  maxConcurrentJobsMin?: number
  maxConcurrentJobsDefaultMax?: number
  maxConcurrentJobsGpuMax?: number
  machineSpecs?: MachineSpec[]
  images?: {[key: string]: Image[]}
}): NewRunnerPayload {
  input = input || {}

  const isPublicIpAllowed = input.isPublicIpAllowed ?? true
  const publicIpInfoPath = 'path/to/public_ip_info'
  const runnerGroups = input.runnerGroups ?? [defaultGroup, anotherGroup]
  const maxConcurrentJobsDefault = input.maxConcurrentJobsDefault ?? 20
  const maxConcurrentJobsMin = input.maxConcurrentJobsMin ?? 1
  const maxConcurrentJobsDefaultMax = input.maxConcurrentJobsDefaultMax ?? 1000
  const maxConcurrentJobsGpuMax = input.maxConcurrentJobsGpuMax ?? 40
  const isCustomImageUploadingEnabled = true
  const machineSpecs = input.machineSpecs ?? [defaultMachineSpec]
  const images = input.images ?? {github: [githubLinuxImage]}
  const isCustomImagesFeatureEnabled = true
  const isCustomImagesPolicyEnabled = true
  const isCustomImagesPolicyFeatureEnabled = true
  const hidePartnerAndCustomTabs = false

  return {
    isEnterprise: false,
    runnerListPath: '/organizations/some-org/actions/runners',
    entityLogin: 'some-org',
    docsUrlBase: 'https://docs.github.com/',
    isPublicIpAllowed,
    publicIpInfoPath,
    runnerGroups,
    maxConcurrentJobsDefault,
    maxConcurrentJobsMin,
    maxConcurrentJobsDefaultMax,
    maxConcurrentJobsGpuMax,
    isCustomImageUploadingEnabled,
    machineSpecs,
    images,
    isCustomImagesFeatureEnabled,
    isCustomImagesPolicyEnabled,
    isCustomImagesPolicyFeatureEnabled,
    hidePartnerAndCustomTabs,
  }
}

export function getEditRunnerRoutePayload(input?: {
  docsUrlBase?: string
  imageVersions?: ImageVersion[]
  isPublicIpAllowed?: boolean
  maxConcurrentJobsMax?: number
  maxConcurrentJobsMin?: number
  runnerGroupId?: number
  runnerGroups?: RunnerGroup[]
  runnerHasCustomImage?: boolean
  runnerHasGpuSpec?: boolean
  runnerHasPublicIp?: boolean
  runnerId?: number
  runnerImageVersion?: string
  runnerListPath?: string
  runnerMaxConcurrentJobs?: number
  runnerName?: string
  publicIpInfoPath?: string
  runnerPlatformId?: string
  images?: {[key: string]: Image[]}
  isCustomImagesFeatureEnabled?: boolean
  runnerImage?: ImageKey
  machineSpecs?: MachineSpec[]
  runnerMachineSpecId?: string
  runnerImageGenerationEnabled?: boolean
}): EditRunnerPayload {
  input = input || {}

  const imageVersions = input.imageVersions ?? []
  const isPublicIpAllowed = input.isPublicIpAllowed ?? true
  const maxConcurrentJobsMax = input.maxConcurrentJobsMax ?? 1000
  const maxConcurrentJobsMin = input.maxConcurrentJobsMin ?? 1
  const runnerGroupId = input.runnerGroupId ?? 1
  const runnerGroups = input.runnerGroups ?? [defaultGroup]
  const runnerHasCustomImage = input.runnerHasCustomImage ?? false
  const runnerHasGpuSpec = input.runnerHasGpuSpec ?? false
  const runnerHasPublicIp = input.runnerHasPublicIp ?? false
  const runnerId = input.runnerId ?? 999
  const runnerMaxConcurrentJobs = input.runnerMaxConcurrentJobs ?? 50
  const runnerName = input.runnerName ?? 'some-runner'
  const publicIpInfoPath = input.publicIpInfoPath ?? 'path/to/public_ip_info'
  const runnerPlatformId = input.runnerPlatformId ?? 'linux-x64'
  const images = input.images ?? {github: []}
  const isCustomImagesFeatureEnabled = input.isCustomImagesFeatureEnabled ?? false
  const runnerImage = input.runnerImage ?? {id: '', source: ImageSource.Curated, version: ''}
  const machineSpecs = input.machineSpecs ?? [defaultMachineSpec]
  const runnerMachineSpecId = input.runnerMachineSpecId ?? defaultMachineSpec.id
  const runnerImageGenerationEnabled = input.runnerImageGenerationEnabled ?? false
  const isCustomImagesPolicyEnabled = true
  const isCustomImagesPolicyFeatureEnabled = true
  const hidePartnerAndCustomTabs = true

  return {
    docsUrlBase: 'https://docs.github.com/',
    entityLogin: 'some-org',
    imageVersions,
    isEnterprise: false,
    isPublicIpAllowed,
    maxConcurrentJobsMin,
    maxConcurrentJobsMax,
    runnerGroupId,
    runnerGroups,
    runnerHasCustomImage,
    runnerHasGpuSpec,
    runnerHasPublicIp,
    runnerId,
    runnerListPath: '/organizations/some-org/actions/runners',
    runnerMaxConcurrentJobs,
    runnerName,
    publicIpInfoPath,
    runnerPlatformId,
    images,
    isCustomImagesFeatureEnabled,
    runnerImage,
    machineSpecs,
    runnerMachineSpecId,
    runnerImageGenerationEnabled,
    isCustomImagesPolicyEnabled,
    isCustomImagesPolicyFeatureEnabled,
    hidePartnerAndCustomTabs,
  }
}

export function getRunnerCreateForm(input?: {
  runnerName?: string
  platform?: PlatformId
  isPublicIpEnabled?: boolean
  imageId?: string | null
  imageSource?: ImageSource
  imageVersion?: string | null
  imageName?: string | null
  imageUploadTypeId?: PlatformId
  imageSasUri?: string
  machineSpecId?: string
}): RunnerCreateForm {
  input = input || {}

  const runnerName = input.runnerName ?? 'some-runner'
  const isPublicIpEnabled = input.isPublicIpEnabled ?? false
  const machineSpecId = input.machineSpecId ?? defaultMachineSpec.id
  const isImageUpload = input.platform === 'custom'
  const isImageGenerationEnabled = false
  const {imageSource, imageId, imageVersion, imageSasUri, imageName, platform} = isImageUpload
    ? {
        imageSource: ImageSource.Custom,
        imageId: null,
        imageVersion: null,
        imageName: null,
        imageSasUri: input.imageSasUri ?? '',
        platform: input.imageUploadTypeId ?? 'linux-x64',
      }
    : {
        imageSource: input.imageSource ?? githubLinuxImage.source,
        imageId: input.imageId ?? githubLinuxImage.id,
        imageVersion: input.imageVersion ?? null,
        imageName: input.imageName ?? `Ubuntu ${githubLinuxImage.displayName}`,
        imageSasUri: '',
        platform: input.platform ?? 'linux-x64',
      }

  return {
    name: runnerName,
    platform: platform ?? null,
    runnerGroupId: 1,
    maximumConcurrentJobs: 20,
    imageId,
    imageSource,
    imageVersion,
    machineSpecId,
    isPublicIpEnabled,
    imageName,
    imageSasUri,
    isImageGenerationEnabled,
  }
}

export function getRunnerEditForm(input?: {
  isPublicIpEnabled?: boolean
  name?: string
  maximumConcurrentJobs?: number
  machineSpecId?: string
  imageId?: string | null
}): RunnerEditForm {
  input = input || {}

  const name = input.name ?? 'some-runner'
  const maximumConcurrentJobs = input.maximumConcurrentJobs ?? 50
  const isPublicIpEnabled = input.isPublicIpEnabled ?? false
  const imageId = input.imageId ?? githubLinuxImage.id

  return {
    imageVersion: null,
    isPublicIpEnabled,
    maximumConcurrentJobs,
    name,
    runnerGroupId: 1,
    machineSpecId: input.machineSpecId ?? defaultMachineSpec.id,
    imageId,
  }
}

export function getImage(input?: Partial<Image>) {
  input = input || {}

  return {
    ...githubLinuxImage,
    ...input,
  } as const satisfies Image
}

export function getMachineSpec(input?: Partial<MachineSpec>) {
  input = input || {}

  return {
    ...defaultMachineSpec,
    ...input,
  } as const satisfies MachineSpec
}

export function getImageVersions(input?: Partial<ImageVersion[]>) {
  input = input || []

  const imageversions = [...input, customImageVersion]
  return imageversions
}
