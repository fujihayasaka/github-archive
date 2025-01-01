import {useCallback} from 'react'
import {graphql, useFragment, useLazyLoadQuery, useRelayEnvironment} from 'react-relay'

import type {ReactionViewerRelayGroups$key} from './__generated__/ReactionViewerRelayGroups.graphql'
import type {ReactionViewerRelayLazyQuery} from './__generated__/ReactionViewerRelayLazyQuery.graphql'
import {VALUES} from './constants/values'
import {addReactionMutation} from './mutations/add-reaction-mutation'
import {removeReactionMutation} from './mutations/remove-reaction-mutation'
import {ReactionViewerBase} from './ReactionViewerBase'
import type {Reaction, ReactionContent, ReactionViewerGroup, Reactor} from './utils/ReactionGroups'

const ReactionGroupsFragment = graphql`
  fragment ReactionViewerRelayGroups on Reactable {
    reactionGroups {
      content
      viewerHasReacted
      reactors(first: 5) {
        totalCount
        nodes {
          __typename
          ... on User {
            login
          }
          ... on Bot {
            login
            isCopilot
          }
          ... on Organization {
            login
          }
          ... on Mannequin {
            login
          }
        }
      }
    }
  }
`

export type ReactionViewerRelayProps = {
  reactionGroups: ReactionViewerRelayGroups$key
  subjectId: string
  canReact?: boolean
}

export function ReactionViewerRelay({reactionGroups, subjectId, canReact = true}: ReactionViewerRelayProps) {
  const environment = useRelayEnvironment()
  const reactionGroupsData = useFragment<ReactionViewerRelayGroups$key>(ReactionGroupsFragment, reactionGroups)

  const onReact = useCallback(
    (reaction: ReactionContent, viewerHasReacted: boolean) => {
      if (!canReact) return
      if (viewerHasReacted) {
        removeReactionMutation({
          environment,
          input: {subject: subjectId, content: reaction},
        })
      } else {
        addReactionMutation({
          environment,
          input: {subject: subjectId, content: reaction},
        })
      }
    },
    [canReact, environment, subjectId],
  )

  // filtering out null reaction groups which can be expected when there's an error on the server
  const reactionViewerGroups = (reactionGroupsData.reactionGroups || [])
    .filter(reactionGroup => Boolean(reactionGroup))
    .map((reactionGroup): ReactionViewerGroup => {
      const reaction: Reaction = {
        content: reactionGroup.content as ReactionContent,
        viewerHasReacted: reactionGroup.viewerHasReacted,
      }

      const reactors: Reactor[] =
        reactionGroup.reactors?.nodes?.map(reactor => {
          if (!reactor || reactor.__typename === '%other') {
            return {login: '', typeName: 'Other'} as Reactor
          }
          const displayName =
            reactor.__typename === 'Bot' && reactor.isCopilot ? VALUES.copilotDisplayName : reactor.login
          return {
            login: displayName,
            typeName: reactor.__typename,
          } as Reactor
        }) || []

      return {
        reaction,
        reactors,
        totalCount: reactionGroup.reactors?.totalCount || 0,
      }
    })

  return (
    <ReactionViewerBase
      reactionGroups={reactionViewerGroups}
      canReact={canReact}
      subjectId={subjectId}
      onReact={onReact}
    />
  )
}

/**
 * Query component for the ReactionViewer, used to fetch the reaction groups for a given subject.
 * @param id The relay ID of the subject to fetch reactions for.
 * @param subjectLocked Whether the subject is locked and reactions should not be allowed.
 * @returns The ReactionViewer component with the fetched reaction groups.
 */
export function ReactionViewerRelayQueryComponent({id, subjectLocked}: {id: string; subjectLocked?: boolean}) {
  const data = useLazyLoadQuery<ReactionViewerRelayLazyQuery>(
    graphql`
      query ReactionViewerRelayLazyQuery($id: ID!) {
        node(id: $id) {
          ... on Comment {
            ...ReactionViewerRelayGroups @dangerously_unaliased_fixme
          }
        }
      }
    `,
    {id},
    {fetchPolicy: 'store-or-network'},
  )

  if (!data.node) {
    return null
  }

  return <ReactionViewerRelay subjectId={id} reactionGroups={data.node} canReact={!subjectLocked} />
}

export default ReactionViewerRelay
