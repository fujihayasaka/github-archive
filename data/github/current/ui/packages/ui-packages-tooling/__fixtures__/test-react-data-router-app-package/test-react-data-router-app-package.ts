import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {testReactDataRouterAppPackageAppBuilder} from './config/app-builder'

import {someRouteRoute} from './routes/some-route-route'
import {SomeRoute} from './routes/SomeRoute'

export const testReactDataRouterAppPackageApp = testReactDataRouterAppPackageAppBuilder.createDataRouterAppFromRoutes([
  someRouteRoute.toRoute({Component: SomeRoute}),
])
registerDataRouterApp(testReactDataRouterAppPackageApp)
