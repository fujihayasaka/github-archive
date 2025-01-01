import {updateUrlHash} from '@github-ui/history'

export function anchorComment(commentDatabaseId: string, anchorPrefix = 'r') {
  updateUrlHash(`#${anchorPrefix}${commentDatabaseId}`)
}
