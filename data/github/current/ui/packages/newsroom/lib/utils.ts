import {ssrSafeLocation} from '@github-ui/ssr-utils'

// date is a string in the format of "YYYY-MM-DD"
export const formatPublishedDate = (date?: string, locale: string = 'en-US') => {
  if (!date) return null

  // Check if the date is valid
  const parsedDate = new Date(date)
  if (isNaN(parsedDate.getTime())) {
    return null
  }

  const options: Intl.DateTimeFormatOptions = {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC', // Ensure the date is treated in UTC for consistency across timezones
  }

  return parsedDate.toLocaleDateString(locale, options)
}

export const appendFeatureFlagsToUrl = (url: string, featureFlags?: string): string => {
  const urlObject = new URL(url, ssrSafeLocation.origin)

  if (featureFlags) {
    urlObject.searchParams.set('_features', featureFlags)
  }

  return urlObject.toString()
}

export const replacePageNumberInUrl = (url: string, pageNumber: number): string => {
  const urlObject = new URL(url, ssrSafeLocation.origin)
  if (urlObject.searchParams.get('page') === '1') {
    urlObject.searchParams.delete('page')
  } else {
    urlObject.searchParams.set('page', pageNumber.toString())
  }

  return urlObject.toString()
}
