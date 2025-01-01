import {App} from './App'
import {Overview} from './routes/Overview'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {Yours, Active, Stale, All} from './routes/List'

registerNavigatorApp('repos-branches', () => ({
  App,
  routes: [
    jsonRoute({path: '/:user_id/:repository/branches', Component: Overview}),
    jsonRoute({path: '/:user_id/:repository/branches/yours', Component: Yours}),
    jsonRoute({path: '/:user_id/:repository/branches/active', Component: Active}),
    jsonRoute({path: '/:user_id/:repository/branches/stale', Component: Stale}),
    jsonRoute({path: '/:user_id/:repository/branches/all', Component: All}),
  ],
}))
