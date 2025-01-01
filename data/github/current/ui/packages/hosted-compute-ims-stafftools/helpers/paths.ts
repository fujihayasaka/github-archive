export const Urls = {
  imsRepoLink: 'https://github.com/github/hosted-compute-ims',
  featureFlagUrl: (featureFlag: string) => `https://devportal.githubapp.com/feature-flags/${featureFlag}`,
}

export function homepagePath() {
  return '/stafftools/hosted_compute_ims_admin'
}

function getCuratedRoot() {
  return `${homepagePath()}/curated`
}

export function createCuratedImagePath() {
  return `${getCuratedRoot()}/create_image`
}

export function createCuratedImagePointerPath() {
  return `${getCuratedRoot()}/create_pointer`
}

export function updateCuratedImagePath() {
  return `${getCuratedRoot()}/update_image`
}

export function updateCuratedImagePointerPath() {
  return `${getCuratedRoot()}/update_pointer`
}

export function deleteCuratedImagePath() {
  return `${getCuratedRoot()}/delete_image`
}

export function deleteCuratedImagePointerPath() {
  return `${getCuratedRoot()}/delete_pointer`
}

export function curatedImagePath(imageDefinitionId: number) {
  return `${getCuratedRoot()}/${imageDefinitionId}`
}

export function updateCuratedImageVersionPath(imageDefinitionId: number) {
  return `${getCuratedRoot()}/${imageDefinitionId}/update_image_version`
}

export function deleteCuratedImageVersionPath(imageDefinitionId: number) {
  return `${getCuratedRoot()}/${imageDefinitionId}/delete_image_version`
}

export function getImageReferencePath(imageDefinitionId: number, version: string) {
  return `${getCuratedRoot()}/${imageDefinitionId}/versions/${version}/image_reference`
}
