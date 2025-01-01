import styles from './assignees.module.css'
import {Link} from '@primer/react'
import {hovercardAttributesForActor} from '@github-ui/hovercards'
import {VALUES} from '../constants/values'
import {graphql} from 'react-relay'
import {useFragment} from 'react-relay/hooks'
import type {AssignmentEventAssignee$key} from './__generated__/AssignmentEventAssignee.graphql'

export const AssignmentEventAssigneeFragment = graphql`
  fragment AssignmentEventAssignee on Actor {
    ... on User {
      __typename
      login
      resourcePath
    }
    ... on Mannequin {
      __typename
      login
      resourcePath
    }
    ... on Organization {
      __typename
      login
      resourcePath
    }
    ... on Bot {
      __typename
      login
      resourcePath
      isCopilot
    }
  }
`

type AssignmentEventAssigneeProps = {
  assigneeRef?: AssignmentEventAssignee$key | undefined | null
}

export function AssignmentEventAssignee({assigneeRef}: AssignmentEventAssigneeProps): JSX.Element {
  const assignee = useFragment(AssignmentEventAssigneeFragment, assigneeRef)

  if (assignee?.__typename === '%other') return <></>

  const assigneeLogin = assignee?.login || VALUES.ghost.login
  const isCopilot = assignee?.__typename === 'Bot' && assignee.isCopilot
  const isUser = assignee?.__typename === 'User' || assignee?.__typename === 'Organization'
  const showHovercard = isUser || isCopilot
  const hovercardData = showHovercard ? hovercardAttributesForActor(assigneeLogin, {isCopilot}) : {}
  const displayName = isCopilot ? VALUES.copilot.displayName : assigneeLogin || VALUES.ghost.login
  return (
    <Link {...hovercardData} href={assignee?.resourcePath} className={styles.assigneeLink} inline>
      {displayName}
    </Link>
  )
}
