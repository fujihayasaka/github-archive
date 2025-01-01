import {App} from './App'
import {AccessPolicyShow} from './routes/AccessPolicyShow'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {repositorySettingsModelsAccessPolicyPath} from '@github-ui/paths'

registerNavigatorApp('github-models-repo-settings', () => ({
  App,
  routes: [
    jsonRoute({
      path: repositorySettingsModelsAccessPolicyPath({
        owner: ':org',
        repo: ':repo',
      }),
      Component: AccessPolicyShow,
    }),
  ],
}))
