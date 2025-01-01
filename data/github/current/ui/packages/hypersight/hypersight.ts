import {App} from './App'
import {Hypersight} from './routes/Hypersight'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('hypersight', () => ({
  App,
  routes: [jsonRoute({path: '/:user_id/:repository/pull/:id/walkthrough', Component: Hypersight})],
}))
