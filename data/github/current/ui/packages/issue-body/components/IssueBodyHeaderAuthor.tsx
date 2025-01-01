import {userHovercardPath} from '@github-ui/paths'
import {Link} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import {VALUES} from '../constants/values'
import type {IssueBodyHeaderAuthor$key} from './__generated__/IssueBodyHeaderAuthor.graphql'

export function IssueBodyHeaderAuthor({author}: {author: IssueBodyHeaderAuthor$key | null; showLogin?: boolean}) {
  const data = useFragment(
    graphql`
      fragment IssueBodyHeaderAuthor on Actor {
        login
        profileUrl
      }
    `,
    author,
  )

  const {login, profileUrl} = data || VALUES.ghost
  return (
    <Link
      href={profileUrl || undefined}
      data-hovercard-url={userHovercardPath({owner: login})}
      data-testid="issue-body-header-author"
      sx={{
        color: 'fg.default',
        fontWeight: 500,
        gridArea: 'login',
        flexShrink: 1,
        overflow: 'hidden',
        whiteSpace: 'nowrap',
        textOverflow: 'ellipsis',
        alignSelf: 'flex-end',
      }}
    >
      {login}
    </Link>
  )
}
