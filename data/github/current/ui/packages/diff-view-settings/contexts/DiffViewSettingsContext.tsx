import {useCurrentUser} from '@github-ui/current-user'
import {useSearchParams} from '@github-ui/use-navigate'
import type React from 'react'
import {createContext, useCallback, useContext, useMemo, useState} from 'react'

import {updateDiffLineSpacingPreference} from '../hooks/use-update-diff-line-spacing-preference'
import {updateDiffViewPreference} from '../hooks/use-update-diff-view-preference'
import type {DiffViewSettings, DiffLineSpacing, SplitPreference} from '../types'

const defaultViewSettings: DiffViewSettingsContextProps = {
  hideWhitespace: false,
  splitPreference: 'split',
  lineSpacing: 'relaxed',
  updateHideWhitespace: () => {},
  updateSplitPreference: () => {},
  updateLineSpacing: () => {},
}

type DiffViewSettingsContextProps = {
  updateHideWhitespace: (newPreference: boolean) => void
  updateSplitPreference: (newPreference: SplitPreference) => void
  updateLineSpacing: (newPreference: DiffLineSpacing) => void
} & DiffViewSettings

const DiffViewSettingsContext = createContext<DiffViewSettingsContextProps>(defaultViewSettings)

export function DiffViewSettingsProvider({
  viewSettings,
  children,
}: React.PropsWithChildren<{viewSettings: DiffViewSettings}>) {
  const currentUser = useCurrentUser()

  // user + query params preferences
  const userSplitPreference = useSplitViewPreference(viewSettings.splitPreference)
  const userWhitespaceParam = useWhitespacePreference(viewSettings.hideWhitespace)
  const userLineSpacing = viewSettings.lineSpacing

  // context state variables
  const [splitPreference, setSplitPreference] = useState(userSplitPreference)
  const [hideWhitespace, setHideWhitespace] = useState(userWhitespaceParam)
  const [lineSpacing, setLineSpacing] = useState<DiffLineSpacing>(userLineSpacing)

  // update user preferences
  const updateSplitPreference = useCallback(async (newPreference: SplitPreference) => {
    updateQueryParam('diff', newPreference)
    setSplitPreference(newPreference)
    await updateDiffViewPreference(newPreference)
  }, [])

  // TODO update persisted user whitespace preference
  const updateHideWhitespace = useCallback((newPreference: boolean) => {
    updateQueryParam('w', newPreference ? '1' : '0')
    setHideWhitespace(newPreference)
  }, [])

  const updateLineSpacing = useCallback(
    async (newPreference: DiffLineSpacing) => {
      setLineSpacing(newPreference)
      await updateDiffLineSpacingPreference(newPreference, currentUser)
    },
    [currentUser],
  )

  const diffViewSettings = useMemo(
    () => ({
      hideWhitespace,
      splitPreference,
      lineSpacing,
      updateHideWhitespace,
      updateSplitPreference,
      updateLineSpacing,
    }),
    [hideWhitespace, lineSpacing, splitPreference, updateHideWhitespace, updateLineSpacing, updateSplitPreference],
  )

  return <DiffViewSettingsContext.Provider value={diffViewSettings}>{children}</DiffViewSettingsContext.Provider>
}

export function useDiffViewSettings() {
  return useContext(DiffViewSettingsContext)
}

function useSplitViewPreference(defaultPreference: SplitPreference): SplitPreference {
  let splitPreference = defaultPreference

  const [searchParams] = useSearchParams()
  const splitPreferenceParam = searchParams.get('diff')

  if (splitPreferenceParam === 'split' || splitPreferenceParam === 'unified') {
    splitPreference = splitPreferenceParam
  }

  return splitPreference
}

function useWhitespacePreference(defaultPreference: boolean): boolean {
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

function updateQueryParam(paramName: string, value: string) {
  const url = new URL(window.location.href, window.location.origin)

  if (value) {
    const encodedValue = encodeURIComponent(value)
    url.searchParams.set(paramName, encodedValue)
  } else {
    url.searchParams.delete(paramName)
  }
  window.history.replaceState({path: url.toString()}, '', url.toString())
}
