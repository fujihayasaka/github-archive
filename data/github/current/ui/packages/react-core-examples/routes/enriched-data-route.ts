import {mainQuery} from '@github-ui/react-core/future/main-query'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'
import type {DeferredPull, Pull, User} from '../data-types'

type EnrichedDataPayload = {
  user: User
  pulls: Pull[]
}

type DeferredEnrichedPayload = {
  pulls: DeferredPull[]
}

export const reactCoreExamplesEnrichedDataRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesEnrichedDataRoute',
  {
    path: '/_react_core_examples/enriched_data',
    queries: [
      mainQuery<EnrichedDataPayload>(),
      {
        queryName: 'enrichedPulls',
        queryDeps: ({pathname}) => ({
          pathname: `${pathname}/deferred`,
        }),
        queryFn: async queryKey => queryFnFetch<DeferredEnrichedPayload>(queryKey),
      },
      {
        queryName: 'badQuery',
        queryFn: async () => {
          throw new Error('bad query')
        },
      },
    ],
  },
)
