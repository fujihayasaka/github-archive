import type {ImageDefinition, OwnerId} from '../types/types'

export type SelectedImagesTab = 'github-images' | 'partner-images' | 'pointers' | 'azuredevops-images'

export function rootUrl(selectedImagesTab?: SelectedImagesTab): string {
  if (selectedImagesTab) {
    return `/stafftools/hosted_compute_ims_admin?tab=${selectedImagesTab}`
  }

  return '/stafftools/hosted_compute_ims_admin'
}

export function rootUrlForOwnerId(ownerId: OwnerId): string {
  if (ownerId === 'github') {
    return rootUrl('github-images')
  } else if (ownerId === 'partner') {
    return rootUrl('partner-images')
  }

  return rootUrl()
}

export function rootUrlForImageDefinition(imageDefinition: ImageDefinition): string {
  if (imageDefinition.pointsToImageDefinitionId) {
    return rootUrl('pointers')
  }

  return rootUrlForOwnerId(imageDefinition.ownerId)
}

export function curatedImageDetailsUrl(imageDefinitionId: number): string {
  return `${rootUrl()}/curated_images/${imageDefinitionId}`
}

export function curatedImageVersionDetailsUrl(imageDefinitionId: number, imageVersion: string): string {
  return `${rootUrl()}/curated_images/${imageDefinitionId}/versions/${imageVersion}`
}

export function manageCuratedImagesUrl(): string {
  return `${rootUrl()}/manage_curated_images`
}

export function manageCuratedImageVersionUrl(): string {
  return `${rootUrl()}/manage_curated_image_versions`
}

export function manageCuratedPointersUrl(): string {
  return `${rootUrl()}/manage_curated_pointers`
}

export function featureFlagUrl(featureFlag: string): string {
  return `https://devportal.githubapp.com/feature-flags/${featureFlag}`
}
