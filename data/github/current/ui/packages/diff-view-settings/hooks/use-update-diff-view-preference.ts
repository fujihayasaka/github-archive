import {verifiedFetch} from '@github-ui/verified-fetch'

import type {SplitPreference} from '../types'

const UPDATE_VIEW_PREFERENCES_URL = '/users/diffview'

export async function updateDiffViewPreference(newPreference: SplitPreference) {
  if (newPreference === 'split') {
    verifiedFetch(`${UPDATE_VIEW_PREFERENCES_URL}?diff=split`, {method: 'POST'})
  } else if (newPreference === 'unified') {
    verifiedFetch(`${UPDATE_VIEW_PREFERENCES_URL}?diff=unified`, {method: 'POST'})
  }
}
