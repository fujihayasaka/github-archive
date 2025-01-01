import {GitHubAvatar} from '@github-ui/github-avatar'

import type {Author} from '../utilities/workspace-editor-types'

const ghostUser: Author = {
  avatarUrl: 'https://avatars.githubusercontent.com/ghost',
  displayLogin: 'ghost',
}

export const SuggesterAvatar = ({className, suggester}: {className?: string; suggester?: Author}) => {
  suggester = suggester || ghostUser
  return (
    <span className={className}>
      <GitHubAvatar className="flex-shrink-0" src={suggester.avatarUrl} size={20} />
    </span>
  )
}
