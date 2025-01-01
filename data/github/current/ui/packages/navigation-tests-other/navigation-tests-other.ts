import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {navigationTestsOtherAppBuilder} from './config/app-builder'

import {indexRoute} from './routes/index-route'
import {Index} from './routes/Index'

export const navigationTestsOtherApp = navigationTestsOtherAppBuilder.createDataRouterAppFromRoutes([
  indexRoute.toRoute({Component: Index}),
])
registerDataRouterApp(navigationTestsOtherApp)
