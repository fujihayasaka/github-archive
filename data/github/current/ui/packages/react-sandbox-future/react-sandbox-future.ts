import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {reactSandboxFutureAppBuilder} from './config/app-builder'
import {reactSandboxFutureLayoutRoute} from './routes/layout-route'
import {ReactSandboxFutureLayout} from './routes/Layout'
import {reactSandboxFutureIndexRoute} from './routes/index-route'
import {ReactSandboxFutureIndex} from './routes/Index'
import {reactSandboxFutureIdRoute} from './routes/id-route'
import {reactSandboxFutureDashboardRoute} from './routes/dashboard-route'
import {ReactSandboxFutureId} from './routes/Id'
import {ReactSandboxFutureDashboard} from './routes/Dashboard'
import {reactSandboxFutureDashboardIssuesRoute} from './routes/dashboard-issues-route'
import {Issues} from './routes/Issues'
import {reactSandboxFutureDashboardPullsRoute} from './routes/dashboard-pulls-route'
import {Pulls} from './routes/Pulls'

export const reactSandboxFutureApp = reactSandboxFutureAppBuilder.createDataRouterAppFromRoutes([
  reactSandboxFutureLayoutRoute.toRoute({
    Component: ReactSandboxFutureLayout,
    children: [
      reactSandboxFutureIndexRoute.toRoute({Component: ReactSandboxFutureIndex}),
      reactSandboxFutureIdRoute.toRoute({Component: ReactSandboxFutureId}),
      reactSandboxFutureDashboardRoute.toRoute({
        Component: ReactSandboxFutureDashboard,
        children: [
          reactSandboxFutureDashboardIssuesRoute.toRoute({Component: Issues}),
          reactSandboxFutureDashboardPullsRoute.toRoute({Component: Pulls}),
        ],
      }),
    ],
  }),
])

registerDataRouterApp(reactSandboxFutureApp)
