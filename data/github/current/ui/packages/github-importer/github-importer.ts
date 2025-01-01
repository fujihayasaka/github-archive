import {App} from './App'
import {ImportView} from './routes/ImportView'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('github-importer', () => ({
  App,
  routes: [jsonRoute({path: '/:owner/:repo/import', Component: ImportView})],
}))
