import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {navigationTestsAppBuilder} from './config/app-builder'

import {layoutRoute} from './routes/layout-route'
import {Layout} from './routes/Layout'
import {showRoute} from './routes/show-route'
import {Show} from './routes/Show'
import {indexRoute} from './routes/index-route'
import {Index} from './routes/Index'

export const navigationTestsApp = navigationTestsAppBuilder.createDataRouterAppFromRoutes([
  layoutRoute.toRoute({
    Component: Layout,
    children: [indexRoute.toRoute({Component: Index}), showRoute.toRoute({Component: Show})],
  }),
])
registerDataRouterApp(navigationTestsApp)
