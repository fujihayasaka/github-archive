import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
import {mainQuery} from '@github-ui/react-core/future/query-configs'
import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'

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
      mainQuery<SandboxBlockingPayload>({queryDeps: ({pathname}) => ({pathname})}),
      {
        queryName: 'deferredPayload',
        queryDeps: ({params}) => {
          return {pathname: `/_react_sandbox_future/${params.id}/deferred`}
        },
        queryFn: async queryKey => queryFnFetch<SandboxDeferredPayload>(queryKey),
        type: QueryRouteQueryType.Deferred,
      },
    ],
  },
)
