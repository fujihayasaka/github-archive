import safeStorage from '@github-ui/safe-storage'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useCallback, useState} from 'react'

import type {DiffStyle} from './workspace-editor-types'

const sessionStorage = safeStorage('sessionStorage', {
  throwQuotaErrorsOnSet: false,
  ttl: 1000 * 60 * 60 * 24,
})

const DIFF_STYLE_KEY = 'WORKSPACE_EDITOR_DIFF_STYLE'
const PREFERENCES_URL = '/repos/preferences'

export const getPreferredDiffStyle = (): DiffStyle | null => {
  const diffStyle = sessionStorage.getItem(DIFF_STYLE_KEY)
  switch (diffStyle) {
    case 'inline':
    case 'split':
      return diffStyle
    default:
      return null
  }
}

export const setPreferredDiffStyle = (diffStyle: DiffStyle) => {
  sessionStorage.setItem(DIFF_STYLE_KEY, diffStyle)
}

export const setTreeExpanded = (treeExpanded: boolean) => {
  setBooleanPreference('copilot_tree_view_expanded_preference', treeExpanded)
}

export const setShowDiff = (diffHidden: boolean) => {
  setBooleanPreference('copilot_show_diff_preference', diffHidden)
}

const setBooleanPreference = (key: string, value: boolean) => {
  const formData = new FormData()
  formData.set(key, value ? 'true' : 'false')
  verifiedFetch(PREFERENCES_URL, {
    method: 'PUT',
    body: formData,
    headers: {Accept: 'application/json'},
  })
}

export function useUserPreference<T>(
  key: string,
  startValue: T,
  valueToString: (value: T) => string,
  saveChanges?: boolean,
) {
  const [preference, setPreference] = useState(startValue)

  const updatePreference = useCallback(
    async (newValue: T) => {
      if (saveChanges) {
        const formData = new FormData()
        formData.set(key, valueToString(newValue))
        verifiedFetch('/repos/preferences', {
          method: 'PUT',
          body: formData,
          headers: {Accept: 'application/json'},
        })
      }
      setPreference(newValue)
    },
    [key, valueToString, saveChanges],
  )

  return {preference, updatePreference}
}
