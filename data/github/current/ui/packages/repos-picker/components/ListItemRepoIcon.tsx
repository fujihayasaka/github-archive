import {RepoIcon, RepoLockedIcon} from '@primer/octicons-react'

export function ListItemRepoIcon({visibility}: {visibility: string}) {
  switch (visibility) {
    case 'public':
      return <RepoIcon aria-label={getAriaLabel(visibility)} size={16} />
    case 'private':
    case 'internal':
      return <RepoLockedIcon aria-label={getAriaLabel(visibility)} size={16} />
    default:
      return <RepoIcon size={16} />
  }
}

function getAriaLabel(visibility: string) {
  switch (visibility) {
    case 'public':
      return 'Public repository:'
    case 'private':
      return 'Private repository:'
    case 'internal':
      return 'Internal repository:'
    default:
      return 'Repository:'
  }
}
