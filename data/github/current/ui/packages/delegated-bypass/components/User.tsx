import {GitHubAvatar} from '@github-ui/github-avatar'
import {Link} from '@primer/react'
import {userHovercardPath} from '@github-ui/paths'
import type {User} from '@github-ui/user-selector'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

export function User({user}: {user: User}) {
  const rulesA11y = useFeatureFlag('rules_a11y')

  return (
    <Link
      inline={rulesA11y}
      aria-label={`View ${user.login} profile`}
      href={user.path}
      className="color-fg-default text-emphasized d-flex flex-items-center"
    >
      <GitHubAvatar
        className="mr-1 cursor-pointer"
        size={16}
        src={user.primaryAvatarUrl}
        data-hovercard-url={userHovercardPath({owner: user.login})}
        square={user.path.startsWith('/apps/')}
      />
      <span>{user.login}</span>
    </Link>
  )
}

export function HoverCardUser({user}: {user: User}) {
  const rulesA11y = useFeatureFlag('rules_a11y')

  return (
    <Link
      inline={rulesA11y}
      aria-label={`View ${user.login} profile`}
      href={user.path}
      className="fgColor-muted"
      data-hovercard-url={userHovercardPath({owner: user.login})}
    >
      {user.login}
    </Link>
  )
}
