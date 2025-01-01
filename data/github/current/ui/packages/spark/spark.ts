import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import Spark from './routes/Spark'

registerNavigatorApp('spark', () => ({
  App,
  routes: [jsonRoute({path: '/spark/apps', Component: Spark})],
}))
