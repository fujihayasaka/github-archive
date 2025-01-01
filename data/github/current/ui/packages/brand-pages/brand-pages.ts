import {App} from './App'
import {Home} from './routes/Home'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('brand-pages', () => ({
  App,
  routes: [jsonRoute({path: '/', Component: Home})],
}))
