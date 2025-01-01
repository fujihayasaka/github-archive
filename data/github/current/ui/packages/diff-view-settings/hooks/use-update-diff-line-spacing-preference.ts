import {userDiffLineSpacingSettingPath} from '@github-ui/paths'
import type {CurrentUser} from '@github-ui/repos-types'
import {verifiedFetch} from '@github-ui/verified-fetch'

import type {DiffLineSpacing} from '../types'

export async function updateDiffLineSpacingPreference(spacingValue: DiffLineSpacing, currentUser?: CurrentUser) {
  if (!currentUser) {
    return
  }

  const formData = new FormData()
  formData.set('diff_line_spacing', spacingValue)

  verifiedFetch(userDiffLineSpacingSettingPath(currentUser), {
    method: 'PUT',
    body: formData,
    headers: {Accept: 'application/json'},
  })
}
