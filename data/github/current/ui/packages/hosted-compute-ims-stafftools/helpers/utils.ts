import type {ImageDefinition, ImageDefinitionEnabled} from '../types/types'

export function validateImageDefinitionName(imageName: string): boolean {
  if (imageName !== imageName.trim()) {
    return false
  }
  const nameRegex = /^[a-zA-Z0-9()._ -]{1,100}$/
  return nameRegex.test(imageName)
}

export function validateFeatureFlag(enabled: ImageDefinitionEnabled, featureFlag: string): boolean {
  if (enabled !== 'FeatureFlag') {
    return true
  }

  if (featureFlag !== featureFlag.trim()) {
    return false
  }
  const flagRegex = /^ims_[a-z0-9_]{1,40}$/
  return flagRegex.test(featureFlag)
}

export function splitCuratedImageDefinitions(images: ImageDefinition[]): {
  imageDefinitionsList: ImageDefinition[]
  imagePointersList: ImageDefinition[]
} {
  const imageDefinitionsList = []
  const imagePointersList = []
  for (const im of images) {
    if (im.pointsToImageDefinitionId) {
      imagePointersList.push(im)
    } else {
      imageDefinitionsList.push(im)
    }
  }
  return {imageDefinitionsList, imagePointersList}
}

export function getImageDefinitionEnabledStatus(imageDefinition: ImageDefinition): ImageDefinitionEnabled {
  if (imageDefinition.featureFlag) {
    return 'FeatureFlag'
  }
  return imageDefinition?.enabled ? 'Enabled' : 'Disabled'
}
