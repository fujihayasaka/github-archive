import {userPRFileTreeVisibilitySettingPath} from '@github-ui/paths'
import {verifiedFetch} from '@github-ui/verified-fetch'

export type FileTreePreferenceUser = {
  login: string
}

export async function updateFileTreePreference(treeValue: boolean, currentUser?: FileTreePreferenceUser) {
  if (!currentUser) {
    return
  }

  const formData = new FormData()
  formData.set('file_tree_visible', treeValue ? 'true' : 'false')

  verifiedFetch(userPRFileTreeVisibilitySettingPath(currentUser), {
    method: 'PUT',
    body: formData,
    headers: {Accept: 'application/json'},
  })
}
