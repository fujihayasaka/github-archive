import {updateSearchParams} from '@github-ui/history'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
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
  const imsFlagRegex = /^ims_[a-z0-9_]{1,40}$/
  const lhrFlagRegex = /^larger_runners_[a-z0-9_]{1,40}$/
  return imsFlagRegex.test(featureFlag) || lhrFlagRegex.test(featureFlag)
}

export function getImageDefinitionEnabledStatus(imageDefinition: ImageDefinition): ImageDefinitionEnabled {
  if (imageDefinition.featureFlag) {
    return 'FeatureFlag'
  }
  return imageDefinition?.enabled ? 'Enabled' : 'Disabled'
}

export function changeUrlParam(key: string, value: string): void {
  const url = new URL(document.location.href, window.location.origin)
  const urlParams = new URLSearchParams(url.search)
  urlParams.set(key, value)
  updateSearchParams(urlParams)
}

export function getLastUrlSegment(): string {
  const urlSegments = ssrSafeLocation.href.split('/')
  return urlSegments[urlSegments.length - 1] || ''
}

export function formatDateString(date: Date): string {
  return date.toLocaleDateString('en-us', {year: 'numeric', month: 'short', day: 'numeric'})
}
