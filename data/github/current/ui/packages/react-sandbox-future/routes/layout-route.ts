import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import {mainQuery} from '@github-ui/react-core/future/query-configs'

export const reactSandboxFutureLayoutRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureLayoutRoute',
  {
    path: '/_react_sandbox_future',
    queries: [
      mainQuery<{someField: string; serverTime: string; tabCounts: {'1': number; '2': number; '3': number}}>({
        queryDeps: ({pathname}) => ({pathname}),
      }),
    ],
  },
)
