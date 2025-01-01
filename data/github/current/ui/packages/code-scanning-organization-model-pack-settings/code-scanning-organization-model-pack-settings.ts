import {App} from './App'
import {ModelPacks} from './routes/ModelPacks'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('code-scanning-organization-model-pack-settings', () => ({
  App,
  routes: [
    jsonRoute({path: 'organizations/:organization_id/settings/code_scanning/model_packs', Component: ModelPacks}),
  ],
}))
