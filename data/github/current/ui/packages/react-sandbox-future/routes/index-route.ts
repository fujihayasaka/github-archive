import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import {mainQuery} from '@github-ui/react-core/future/query-configs'

export const reactSandboxFutureIndexRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureIndexRoute',
  {
    path: '/_react_sandbox_future',
    index: true,
    queries: [mainQuery<{someField: string; serverTime: string}>({queryDeps: ({pathname}) => ({pathname})})],
  },
)
