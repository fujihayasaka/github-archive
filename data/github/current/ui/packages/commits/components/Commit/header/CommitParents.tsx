import type {RepositoryNWO} from '@github-ui/current-repository'
import {commitHovercardPath, commitPath} from '@github-ui/paths'
import {Link} from '@github-ui/react-core/link'
import {Link as PrimerLink} from '@primer/react'
import {Fragment} from 'react'

import type {CommitExtended} from '../../../types/commit-types'
import {grabAndAppendUrlParameters} from '../../../utils/grab-and-append-url-parameters'
import {shortSha} from '../../../utils/short-sha'

type CommitParentsProps = {
  commit: CommitExtended
  repo: RepositoryNWO
}

export function CommitParents({commit, repo}: CommitParentsProps) {
  return (
    <>
      {`${commit.parents.length} parent${commit.parents.length > 1 || commit.parents.length === 0 ? 's' : ''} `}
      {commit.parents.map((parent, index) => {
        return (
          <Fragment key={parent}>
            {index !== 0 ? ' + ' : ''}
            <PrimerLink
              to={
                commitPath({owner: repo.ownerLogin, repo: repo.name, commitish: parent}) + grabAndAppendUrlParameters()
              }
              as={Link}
              className="color-fg-default Link--inTextBlock"
              data-hovercard-url={commitHovercardPath({
                owner: repo.ownerLogin,
                repo: repo.name,
                commitish: parent,
              })}
            >
              {shortSha(parent)}
            </PrimerLink>
          </Fragment>
        )
      })}
    </>
  )
}
