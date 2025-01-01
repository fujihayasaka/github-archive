import {mainQuery} from '@github-ui/react-core/future/main-query'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

import {reactSandboxFutureAppBuilder} from '../config/app-builder'

type SandboxBlockingPayload = {someField: string; serverTime: string}

type SandboxDeferredPayload = {
  someDeferredField: string
  deferredLoadedAt: string
}

export const reactSandboxFutureIdRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureIdRoute',
  {
    path: '/_react_sandbox_future/:id',
    queries: [
      mainQuery<SandboxBlockingPayload>(),
      {
        queryName: 'deferredPayload',
        queryDeps: ({params}) => {
          return {pathname: `/_react_sandbox_future/${params.id}/deferred`}
        },
        queryFn: async queryKey => queryFnFetch<SandboxDeferredPayload>(queryKey),
      },
    ],
  },
)
