import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import App from './App'
import CopilotImmersiveLoggedOut from './routes/CopilotImmersiveLoggedOut'

registerNavigatorApp('copilot-immersive-logged-out', () => ({
  App,
  routes: [jsonRoute({path: '/copilot', Component: CopilotImmersiveLoggedOut})],
}))
