import {ssrSafeLocation, ssrSafeWindow} from '@github-ui/ssr-utils'
import {URLS, reservedQueryKeys} from '../constants/urls'

const REPO_ISSUES_SUFFIX = '/issues'
const REPO_NEW_ISSUES_SUFFIX = `${REPO_ISSUES_SUFFIX}/new`
const REPO_CHOOSE_ISSUES_SUFFIX = `${REPO_NEW_ISSUES_SUFFIX}/choose`

export const getTemplateUrl = (nameWithOwner: string, filename: string) => {
  const searchParams = new URLSearchParams(ssrSafeLocation.search || '')
  searchParams.set('template', filename)

  return `/${nameWithOwner}/issues/new?${searchParams.toString()}`
}

export const appendNewToBasePath = (path: string): string => safeUrlAppend(path, REPO_NEW_ISSUES_SUFFIX)
export const appendChooseToBasePath = (path: string): string => safeUrlAppend(path, REPO_CHOOSE_ISSUES_SUFFIX)

const safeUrlAppend = (path: string, append: string): string => {
  // If path already ends with /, ensure we don't add another /
  if (path.endsWith('/')) {
    return path.substring(0, path.length - 1) + append
  }

  return path + append
}

type newTemplateAbsolutePathType = {
  repositoryAbsolutePath: string
  fileName: string
}

export const newTemplateAbsolutePath = ({repositoryAbsolutePath, fileName}: newTemplateAbsolutePathType): string => {
  const newPath = appendNewToBasePath(repositoryAbsolutePath)
  const url = new URL(newPath, ssrSafeWindow?.location?.origin)
  const searchParams = new URLSearchParams(url.search)
  searchParams.set(URLS.queryParams.template, fileName)
  url.search = searchParams.toString()
  return url.toString()
}

export const getPotentialFormDefaultValuesFromUrl = (urlParams?: URLSearchParams): Record<string, string> => {
  const searchParams = urlParams ?? new URLSearchParams(ssrSafeWindow?.location?.search || '')
  const defaultValuesById: Record<string, string> = {}

  for (const [key, value] of searchParams) {
    if (reservedQueryKeys.includes(key)) {
      continue
    } else if (value === null) {
      defaultValuesById[key] = ''
    } else {
      defaultValuesById[key] = value.substring(0, URLS.maxQueryLengthLimits.body)
    }
  }

  return defaultValuesById
}

export const safeStringParamGet = (
  searchParams: URLSearchParams,
  key: string,
  maxLimit: number,
): string | undefined => {
  const value = searchParams.get(key)
  if (value === null) {
    return undefined
  }

  return value.substring(0, maxLimit)
}

export const safeStringParamSet = (
  searchParams: URLSearchParams,
  key: string,
  value: string | undefined,
  maxLimit: number,
): void => {
  if (value === undefined) {
    return
  }

  searchParams.set(key, value.substring(0, maxLimit))
}

export const safeStringArrayParamSet = (
  searchParams: URLSearchParams,
  key: string,
  values: string[] | undefined,
  maxLengthLimit: number,
): void => {
  if (!values) {
    return
  }

  searchParams.set(key, values.slice(0, maxLengthLimit).join(','))
}

export function loginPath() {
  return `/login?return_to=${ssrSafeLocation?.href}`
}

export function getChooseTemplateUrl(nameWithOwner: string) {
  return `/${nameWithOwner}/issues/new/choose`
}
