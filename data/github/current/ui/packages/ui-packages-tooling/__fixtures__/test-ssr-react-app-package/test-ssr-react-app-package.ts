import {App} from './App'
import {SomeRoute} from './routes/SomeRoute'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('test-ssr-react-app-package', () => ({
  App,
  routes: [jsonRoute({path: '/some/:id/route', Component: SomeRoute})],
}))
