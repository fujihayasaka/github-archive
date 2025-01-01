import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {agentSessionsAppBuilder} from './config/app-builder'

import {listSessionsRoute} from './routes/list-sessions'
import {ListSessions} from './routes/ListSessions'
import {showSessionRoute} from './routes/show-session'
import {ShowSession} from './routes/ShowSession'

export const agentSessionsApp = agentSessionsAppBuilder.createDataRouterAppFromRoutes([
  listSessionsRoute.toRoute({Component: ListSessions}),
  showSessionRoute.toRoute({Component: ShowSession}),
])
registerDataRouterApp(agentSessionsApp)
