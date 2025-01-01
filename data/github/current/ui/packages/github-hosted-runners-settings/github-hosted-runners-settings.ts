import {App} from './App'
import {EditRunner} from './routes/EditRunner'
import {NewRunner} from './routes/NewRunner'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('github-hosted-runners-settings', () => ({
  App,
  routes: [
    jsonRoute({
      path: '/organizations/:organization_id/settings/actions/github-hosted-runners/new',
      Component: NewRunner,
    }),
    jsonRoute({
      path: '/organizations/:organization_id/settings/actions/github-hosted-runners/:runner_id/edit',
      Component: EditRunner,
    }),
    jsonRoute({
      path: '/enterprises/:business/settings/actions/github-hosted-runners/new',
      Component: NewRunner,
    }),
    jsonRoute({
      path: '/enterprises/:business/settings/actions/github-hosted-runners/:runner_id/edit',
      Component: EditRunner,
    }),
  ],
}))
