import {App} from './App'
import {registerReactAppFactory} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {CommitsEntrypoint} from './routes/Commits'

registerReactAppFactory('pull-request-commits', () => ({
  App,
  routes: [jsonRoute({path: '/:owner/:repo/pull/:pr_number/commits', Component: CommitsEntrypoint})],
}))
