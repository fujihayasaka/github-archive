import {graphql, useLazyLoadQuery} from 'react-relay'

import type {useMarkdownEditHistoryViewerQueryQuery} from './__generated__/useMarkdownEditHistoryViewerQueryQuery.graphql'

// This hook is used as a stopgap in PRs where relay components are used in a non-relay environment
export function useMarkdownEditHistoryViewerQuery({id}: {id: string}) {
  const data = useLazyLoadQuery<useMarkdownEditHistoryViewerQueryQuery>(
    graphql`
      query useMarkdownEditHistoryViewerQueryQuery($id: ID!) {
        node(id: $id) {
          ... on Comment {
            # eslint-disable-next-line relay/must-colocate-fragment-spreads
            ...MarkdownEditHistoryViewer_comment @dangerously_unaliased_fixme
            # eslint-disable-next-line relay/must-colocate-fragment-spreads
            ...MarkdownLastEditedBy @dangerously_unaliased_fixme
          }
        }
      }
    `,
    {id},
  )

  if (!data.node) {
    return null
  }

  return data.node
}
