import {registerDataRouterApp} from '@github-ui/react-core/register-app'

import {modelsByokSettingsAppBuilder} from './config/app-builder'
import {customModelsIndexRoute} from './routes/CustomModelsIndex/custom-models-index-route'
import {CustomModelsIndex} from './routes/CustomModelsIndex/CustomModelsIndex'

export const modelsByokSettingsApp = modelsByokSettingsAppBuilder.createDataRouterAppFromRoutes(flags => {
  if (flags.isEnabled('github_models_byok')) {
    return [customModelsIndexRoute.toRoute({Component: CustomModelsIndex})]
  }
  return []
})
registerDataRouterApp(modelsByokSettingsApp)
