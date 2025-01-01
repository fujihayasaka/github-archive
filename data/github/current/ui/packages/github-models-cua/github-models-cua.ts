import {registerDataRouterApp} from '@github-ui/react-core/register-app'

import {appBuilder} from './config/app'
import IndexRouteComponent, {modelsCUAIndexRoute} from './routes/ModelsCUAIndexRoute'
import SessionRouteComponent, {modelsCUASessionRoute} from './routes/ModelsCUASessionRoute'

const app = appBuilder.createDataRouterAppFromRoutes([
  modelsCUAIndexRoute.toRoute({Component: IndexRouteComponent}),
  modelsCUASessionRoute.toRoute({Component: SessionRouteComponent}),
])
registerDataRouterApp(app)
