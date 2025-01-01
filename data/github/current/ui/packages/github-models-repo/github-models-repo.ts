import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {App} from './App'
import {ModelsRoute} from './routes/models/ModelsRoute'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {PromptLayout} from './components/PromptLayout'
import {PromptsRoute} from './routes/prompts/PromptsRoute'
import {PromptRoute} from './routes/prompt/PromptRoute'

registerNavigatorApp('github-models-repo', () => ({
  App,
  routes: [
    // Models tab sections
    jsonRoute({path: '/:owner/:repo/models', Component: ModelsRoute}),
    jsonRoute({path: '/:owner/:repo/models/prompts', Component: PromptsRoute}),

    // Prompt management routes
    jsonRoute({
      path: '/:owner/:repo/models/prompt',
      Component: PromptLayout,
      shouldNavigateOnError: true,
      // Do a fast transition without fetch. Prompt and compare share the state, so we don't have to fetch again
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
      children: [
        {
          path: '/:owner/:repo/models/prompt/new',
          Component: PromptRoute,
        },
        {
          path: '/:owner/:repo/models/prompt/edit/:branch/*',
          Component: PromptRoute,
        },
        {
          path: '/:owner/:repo/models/prompt/compare/:branch/*',
          Component: PromptRoute,
        },
        // TODO: CS: Add a separate pull request route?
      ],
    }),
  ],
}))
