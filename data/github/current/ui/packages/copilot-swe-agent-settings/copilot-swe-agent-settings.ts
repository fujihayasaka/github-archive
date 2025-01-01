import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import {RepoSettings} from './routes/RepoSettings'

// eslint-disable-next-line @github-ui/github-monorepo/prefer-data-router
registerNavigatorApp('copilot-swe-agent-settings', () => ({
  App,
  routes: [
    // eslint-disable-next-line @github-ui/github-monorepo/prefer-data-router
    jsonRoute({
      path: '/:owner/:name/settings/copilot/coding_agent',
      Component: RepoSettings,
      transitionType: TransitionType.FETCH_THEN_TRANSITION,
    }),
  ],
}))
