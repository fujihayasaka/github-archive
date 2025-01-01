import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactSandboxFutureAppBuilder} from '../config/app-builder'

export const reactSandboxFutureClientErrorRoute = reactSandboxFutureAppBuilder.createQueryRouteConfig(
  'reactSandboxFutureClientErrorRoute',
  {
    path: '/_react_sandbox_future/client_error',
    queries: [mainQuery<{message: string}>()],
  },
)
