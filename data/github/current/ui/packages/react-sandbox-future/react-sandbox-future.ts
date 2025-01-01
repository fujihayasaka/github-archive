import {registerDataRouterApp} from '@github-ui/react-core/register-app'

import {ClientError} from './components/ClientError'
import {reactSandboxFutureAppBuilder} from './config/app-builder'
import {reactSandboxFutureClientErrorRoute} from './routes/client-error-route'
import {ReactSandboxFutureDashboard} from './routes/Dashboard'
import {reactSandboxFutureDashboardDiscussionsRoute} from './routes/dashboard-discussions-route'
import {reactSandboxFutureDashboardIssuesRoute} from './routes/dashboard-issues-route'
import {reactSandboxFutureDashboardPullsRoute} from './routes/dashboard-pulls-route'
import {reactSandboxFutureDashboardRoute} from './routes/dashboard-route'
import {Discussions} from './routes/Discussions'
import {ReactSandboxFutureId} from './routes/Id'
import {reactSandboxFutureIdRoute} from './routes/id-route'
import {ReactSandboxFutureIndex} from './routes/Index'
import {reactSandboxFutureIndexRoute} from './routes/index-route'
import {Issues} from './routes/Issues'
import {ReactSandboxFutureLayout} from './routes/Layout'
import {reactSandboxFutureLayoutRoute} from './routes/layout-route'
import {Pulls} from './routes/Pulls'

export const reactSandboxFutureApp = reactSandboxFutureAppBuilder.createDataRouterAppFromRoutes([
  reactSandboxFutureLayoutRoute.toRoute({
    Component: ReactSandboxFutureLayout,
    children: [
      reactSandboxFutureIndexRoute.toRoute({Component: ReactSandboxFutureIndex}),
      reactSandboxFutureIdRoute.toRoute({Component: ReactSandboxFutureId}),
      reactSandboxFutureClientErrorRoute.toRoute({Component: ClientError}),
      reactSandboxFutureDashboardRoute.toRoute({
        Component: ReactSandboxFutureDashboard,
        children: [
          reactSandboxFutureDashboardIssuesRoute.toRoute({Component: Issues}),
          reactSandboxFutureDashboardPullsRoute.toRoute({Component: Pulls}),
          reactSandboxFutureDashboardDiscussionsRoute.toRoute({Component: Discussions}),
        ],
      }),
    ],
  }),
])

registerDataRouterApp(reactSandboxFutureApp)
