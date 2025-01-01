import {App} from './App'
import {Index} from './routes/Index'
import {ShowApp} from './routes/ShowApp'
import {ShowAction} from './routes/ShowAction'
import {ModelsPlaygroundRoute} from '@github-ui/github-models/ModelsPlaygroundRoute'
import {ModelsPromptRoute} from '@github-ui/github-models/ModelsPromptRoute'
import {ModelsShowRoute} from '@github-ui/github-models/ModelsShowRoute'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('marketplace-react', () => ({
  App,
  routes: [
    jsonRoute({path: '/marketplace', Component: Index}),
    jsonRoute({path: '/marketplace/:slug', Component: ShowApp}),
    jsonRoute({path: '/marketplace/actions/:slug', Component: ShowAction}),
    jsonRoute({path: '/marketplace/models', Component: ModelsPlaygroundRoute}),
    jsonRoute({path: '/marketplace/models/catalog', Component: Index}),
    jsonRoute({path: '/marketplace/models/:registry/:model', Component: ModelsShowRoute}),
    jsonRoute({path: '/marketplace/models/:registry/:model/playground', Component: ModelsPlaygroundRoute}),
    jsonRoute({path: '/marketplace/models/:registry/:model/playground/code', Component: ModelsPlaygroundRoute}),
    jsonRoute({path: '/marketplace/models/:registry/:model/playground/json', Component: ModelsPlaygroundRoute}),
    // Depending on github_models_prompt_editor feature flag
    jsonRoute({path: '/marketplace/models/:registry/:model/prompt', Component: ModelsPromptRoute}),
    // Depending on github_models_prompt_evals feature flag
    jsonRoute({path: '/marketplace/models/:registry/:model/evals', Component: ModelsPromptRoute}),
  ],
}))
