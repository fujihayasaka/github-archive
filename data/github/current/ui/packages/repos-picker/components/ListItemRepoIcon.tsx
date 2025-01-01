import {RepoIcon, RepoLockedIcon} from '@primer/octicons-react'

export function ListItemRepoIcon({visibility}: {visibility: string}) {
  switch (visibility) {
    case 'public':
      return <RepoIcon size={16} />
    case 'private':
    case 'internal':
      return <RepoLockedIcon size={16} />
    default:
      return <RepoIcon size={16} />
  }
}
