import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import {RepositoriesPage} from './routes/RepositoriesPage'

registerNavigatorApp('repos-list', () => ({
  App,
  routes: [jsonRoute({path: '/orgs/:org/repositories', Component: RepositoriesPage})],
}))
