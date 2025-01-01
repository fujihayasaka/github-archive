import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

import {App} from './App'

import {ModelsPromptRoute} from './routes/prompt/ModelsPromptRoute'
import {ModelsPlaygroundRoute} from './routes/playground/ModelsPlaygroundRoute'
import {ModelsShowRoute} from './routes/show/ModelsShowRoute'

registerNavigatorApp('github-models', () => ({
  App,
  routes: [
    jsonRoute({path: '/marketplace/models', Component: ModelsPlaygroundRoute}),
    jsonRoute({path: '/marketplace/models/:registry/:model', Component: ModelsShowRoute}),
    jsonRoute({path: '/marketplace/models/:registry/:model/prompt', Component: ModelsPromptRoute}),
    jsonRoute({path: '/marketplace/models/:registry/:model/playground', Component: ModelsPlaygroundRoute}),
    jsonRoute({
      path: '/marketplace/models/:registry/:model/playground/code',
      Component: ModelsPlaygroundRoute,
    }),
    jsonRoute({
      path: '/marketplace/models/:registry/:model/playground/json',
      Component: ModelsPlaygroundRoute,
    }),
  ],
}))
