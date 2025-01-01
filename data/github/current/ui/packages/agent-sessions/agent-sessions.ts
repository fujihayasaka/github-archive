import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {agentSessionsAppBuilder} from './config/app-builder'

import {sessionRoute} from './routes/session'
import {Session} from './routes/Session'

export const agentSessionsApp = agentSessionsAppBuilder.createDataRouterAppFromRoutes([
  sessionRoute.toRoute({Component: Session}),
])
registerDataRouterApp(agentSessionsApp)
