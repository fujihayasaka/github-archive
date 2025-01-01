import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {organizationSettingsModelsAccessPolicyPath} from '@github-ui/paths'

import {App} from './App'
import {AccessPolicyShow} from './routes/AccessPolicyShow'

registerNavigatorApp('github-models-org-settings', () => ({
  App,
  routes: [jsonRoute({path: organizationSettingsModelsAccessPolicyPath({org: ':org'}), Component: AccessPolicyShow})],
}))
