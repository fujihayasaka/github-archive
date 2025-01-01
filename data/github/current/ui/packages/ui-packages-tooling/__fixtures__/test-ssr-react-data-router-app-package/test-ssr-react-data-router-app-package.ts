import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {testSsrReactDataRouterAppPackageAppBuilder} from './config/app-builder'

import {someRouteRoute} from './routes/some-route-route'
import {SomeRoute} from './routes/SomeRoute'

export const testSsrReactDataRouterAppPackageApp = testSsrReactDataRouterAppPackageAppBuilder.createDataRouterAppFromRoutes([
  someRouteRoute.toRoute({Component: SomeRoute}),
])
registerDataRouterApp(testSsrReactDataRouterAppPackageApp)
