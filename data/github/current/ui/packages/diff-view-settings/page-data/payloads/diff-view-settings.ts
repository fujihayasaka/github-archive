import {PageData} from '@github-ui/pull-request-page-data-tooling/page-data'
import {useQuery, type QueryKey} from '@github-ui/react-query'
import {useSearchParams} from '@github-ui/use-navigate'
import {updateUrl} from '@github-ui/history'

// TODO replace with const defined in @github-ui/diff-view-settings/types
export const CommentsPreference = {
  Visible: 'visible',
  Collapsed: 'collapsed',
} as const

// TODO replace with types defined in @github-ui/diff-view-settings/types
export type CommentsPreference = (typeof CommentsPreference)[keyof typeof CommentsPreference]
export type DiffLineSpacing = 'compact' | 'relaxed'
export type SplitPreference = 'split' | 'unified'

export const defaultViewSettings: DiffViewSettings = {
  hideWhitespace: false,
  splitPreference: 'split',
  lineSpacing: 'relaxed',
  commentsPreference: CommentsPreference.Visible,
}

// TODO replace with type defined in @github-ui/diff-view-settings/types
export type DiffViewSettings = {
  commentsPreference: CommentsPreference
  hideWhitespace: boolean
  splitPreference: SplitPreference
  lineSpacing: DiffLineSpacing
}

export function diffViewSettingsKey(): QueryKey {
  return [PageData.diffViewUserSettings]
}

export function useDiffViewSettingsData(initialData?: DiffViewSettings) {
  const queryKey = diffViewSettingsKey()

  return useQuery<DiffViewSettings>({
    // eslint-disable-next-line @tanstack/query/exhaustive-deps
    queryKey,
    queryFn: async () => {
      return initialData ? initialData : defaultViewSettings
    },
    initialData,
    staleTime: Infinity,
  })
}

export function updateQueryParam(paramName: string, value: string) {
  const url = new URL(window.location.href, window.location.origin)

  if (value) {
    const encodedValue = encodeURIComponent(value)
    url.searchParams.set(paramName, encodedValue)
  } else {
    url.searchParams.delete(paramName)
  }
  updateUrl(url.toString())
}

export function useSplitViewPreference(defaultPreference: SplitPreference): SplitPreference {
  let splitPreference = defaultPreference

  const [searchParams] = useSearchParams()
  const splitPreferenceParam = searchParams.get('diff')

  if (splitPreferenceParam === 'split' || splitPreferenceParam === 'unified') {
    splitPreference = splitPreferenceParam
  }

  return splitPreference
}

export function useWhitespacePreference(defaultPreference: boolean): boolean {
  let hideWhitespace = defaultPreference

  const [searchParams] = useSearchParams()
  const whitespaceParam = searchParams.get('w')

  if (whitespaceParam === '1') {
    hideWhitespace = true
  } else if (whitespaceParam === '0') {
    hideWhitespace = false
  }

  return hideWhitespace
}
