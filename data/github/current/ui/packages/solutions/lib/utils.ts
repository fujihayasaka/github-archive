import {ssrSafeLocation} from '@github-ui/ssr-utils'

export const appendFeatureFlagsToUrl = (url: string, featureFlags?: string): string => {
  const urlObject = new URL(url, ssrSafeLocation.origin)

  if (featureFlags) {
    urlObject.searchParams.set('_features', featureFlags)
  }

  return urlObject.toString()
}
