import {GitHubAvatar} from '@github-ui/github-avatar'
import {Link} from '@primer/react'
import {userHovercardPath} from '@github-ui/paths'
import type {User} from '@github-ui/user-selector'

import styles from './User.module.css'

export function User({user}: {user: User}) {
  return (
    <>
      <Link aria-label={`View ${user.login} profile`} href={user.path}>
        <GitHubAvatar
          src={user.primaryAvatarUrl}
          data-hovercard-url={userHovercardPath({owner: user.login})}
          square={user.path.startsWith('/apps/')}
          className={styles.GitHubAvatar}
        />
      </Link>
      <Link muted href={user.path} data-hovercard-url={userHovercardPath({owner: user.login})} className={styles.Link}>
        {user.login}
      </Link>
    </>
  )
}
