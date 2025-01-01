import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import App from './App'
import InboxRoutePage from './routes/InboxRoutePage'

registerNavigatorApp('notifications-inbox', () => ({
  App,
  routes: [
    jsonRoute({
      path: '*',
      Component: InboxRoutePage,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
  ],
}))
