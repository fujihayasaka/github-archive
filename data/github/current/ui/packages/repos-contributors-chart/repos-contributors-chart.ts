import {App} from './App'
import {Index} from './routes/Index'
import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('repos-contributors-chart', () => ({
  App,
  routes: [
    jsonRoute({
      path: '/:owner/:repo/graphs/contributors',
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
      Component: Index,
    }),
  ],
}))
