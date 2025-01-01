import {App} from './App'
import {DefaultSetup} from './routes/DefaultSetup'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('repository-code-scanning-settings', () => ({
  App,
  routes: [jsonRoute({path: '/:owner/:repo/settings/code-scanning/default-setup', Component: DefaultSetup})],
}))
