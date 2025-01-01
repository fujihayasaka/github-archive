import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import {EnterpriseSecurityManagers} from './routes/EnterpriseSecurityManagers'

registerNavigatorApp('security-managers', () => ({
  App,
  routes: [jsonRoute({path: '/enterprises/:business/security-managers', Component: EnterpriseSecurityManagers})],
}))
