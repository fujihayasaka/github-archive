import {memo} from 'react'
import {useLazyLoadQuery} from 'react-relay'
import {graphql} from 'relay-runtime'

import type {RelayRouteLazyLoadedQueryViewerQuery} from './__generated__/RelayRouteLazyLoadedQueryViewerQuery.graphql'
import {ViewerLoginAndType} from './ViewerLoginAndType'

export const RelayRouteLazyLoadedQuery = memo(function RelayRouteLazyLoadedQuery() {
  const q = useLazyLoadQuery<RelayRouteLazyLoadedQueryViewerQuery>(
    graphql`
      query RelayRouteLazyLoadedQueryViewerQuery {
        viewer {
          login
        }
      }
    `,
    {},
    {fetchPolicy: 'store-and-network'},
  )

  return <ViewerLoginAndType type="Lazy">{q.viewer.login}</ViewerLoginAndType>
})
