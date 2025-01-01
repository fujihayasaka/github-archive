import {FileAddedIcon, FileDiffIcon, FileMovedIcon, FileRemovedIcon} from '@primer/octicons-react'

import type {PatchStatus} from '@github-ui/diff-file-helpers'

export function FileStatusIcon({status}: {status: PatchStatus}): JSX.Element {
  switch (status) {
    case 'ADDED':
    case 'COPIED':
      return <FileAddedIcon size={16} className="fgColor-success" />
    case 'DELETED':
    case 'REMOVED':
      return <FileRemovedIcon size={16} className="fgColor-danger" />
    case 'RENAMED':
      return <FileMovedIcon size={16} className="fgColor-attention" />
    default:
      return <FileDiffIcon size={16} className="fgColor-muted" />
  }
}
