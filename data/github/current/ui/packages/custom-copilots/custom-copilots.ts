import {App} from './App'
import {NewCustomCopilot} from './routes/NewCustomCopilot'
import {EditCustomCopilot} from './routes/EditCustomCopilot'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('custom-copilots', () => ({
  App,
  routes: [
    jsonRoute({path: '/custom_copilots/new', Component: NewCustomCopilot}),
    jsonRoute({path: '/custom_copilots/:id/edit', Component: EditCustomCopilot}),
  ],
}))
