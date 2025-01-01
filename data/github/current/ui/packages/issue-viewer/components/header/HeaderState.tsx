import {Link, StateLabel} from '@primer/react'
import {graphql, useFragment} from 'react-relay'

import type {HeaderState$key, HeaderState$data} from './__generated__/HeaderState.graphql'
import {TEST_IDS} from '../../constants/test-ids'
import {useIssueState} from '@github-ui/use-issue-state'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'
import {issueHovercardPath} from '@github-ui/paths'

type HeaderStateProps = {
  isSticky: boolean // whether it is rendered in the normal header or in the sticky header
  stateData: HeaderState$key
}

export function HeaderState({isSticky, stateData}: HeaderStateProps) {
  const {state, stateReason, duplicateOf} = useFragment(
    graphql`
      fragment HeaderState on Issue {
        state
        stateReason(enableDuplicate: true)
        duplicateOf {
          number
          url
          repository {
            name
            owner {
              login
            }
          }
        }
      }
    `,
    stateData,
  )
  const {stateString, stateStatus} = useIssueState({
    state,
    stateReason,
    options: {longText: !isSticky},
  })
  const {issues_react_close_as_duplicate} = useFeatureFlags()

  return (
    <div>
      <StateLabel data-testid={TEST_IDS.headerState} status={stateStatus} sx={{whiteSpace: 'nowrap'}}>
        {stateString}
        {issues_react_close_as_duplicate && <DuplicateIssueLink duplicateOf={duplicateOf} />}
      </StateLabel>
    </div>
  )
}

function DuplicateIssueLink({duplicateOf}: {duplicateOf?: HeaderState$data['duplicateOf']}) {
  if (!duplicateOf) return null

  const dataHovercardUrl = issueHovercardPath({
    repo: duplicateOf.repository.name,
    owner: duplicateOf.repository.owner.login,
    issueNumber: duplicateOf.number,
  })

  return (
    <>
      {' '}
      of
      <Link href={duplicateOf?.url} inline sx={{color: 'fg.onEmphasis', ml: 1}} data-hovercard-url={dataHovercardUrl}>
        #{duplicateOf?.number}
      </Link>
    </>
  )
}
