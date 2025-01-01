import {App} from './App'
import {Index} from './routes/Index'
import {registerReactAppFactory} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerReactAppFactory('copilot-immersive-unlicensed', () => ({
  App,
  routes: [jsonRoute({path: '/copilot', Component: Index})],
}))
