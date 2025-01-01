import {App} from './App'
import {Index} from './routes/Index'
import {ShowApp} from './routes/ShowApp'
import {ShowAction} from './routes/ShowAction'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('marketplace-react', () => ({
  App,
  routes: [
    jsonRoute({path: '/marketplace', Component: Index}),
    jsonRoute({path: '/marketplace/:slug', Component: ShowApp}),
    jsonRoute({path: '/marketplace/actions/:slug', Component: ShowAction}),
    jsonRoute({path: '/marketplace/models/catalog', Component: Index}),
  ],
}))
