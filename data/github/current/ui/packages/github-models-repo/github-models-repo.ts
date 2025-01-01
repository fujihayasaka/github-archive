import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {App} from './App'
import {PromptLayout} from './components/PromptLayout'
import {ModelsRoute} from './routes/models/ModelsRoute'
import {PromptRoute} from './routes/prompt/PromptRoute'
import {ReviewRoute} from './routes/prompt/ReviewRoute'
import {PromptsRoute} from './routes/prompts/PromptsRoute'
import {PlaygroundRoute} from './routes/playground/PlaygroundRoute'
import {BlankSlatePlaygroundRoute} from './routes/playground/BlankSlatePlaygroundRoute'
import {ComparisonsRoute} from './routes/comparisons/ComparisonsRoute'

registerNavigatorApp('github-models-repo', () => ({
  App,
  routes: [
    // Models tab sections
    jsonRoute({path: '/:owner/:repo/models', Component: ModelsRoute}),
    jsonRoute({path: '/:owner/:repo/models/prompts', Component: PromptsRoute}),
    jsonRoute({path: '/:owner/:repo/models/comparisons', Component: ComparisonsRoute}),

    // Prompt management routes
    jsonRoute({
      path: '/:owner/:repo/models/prompt',
      Component: PromptLayout,
      shouldNavigateOnError: true,
      // Fetch during the transition. This prevents bugs where the app payload is null when switching back and forth between tabs
      transitionType: TransitionType.TRANSITION_WHILE_FETCHING,
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
      ],
    }),

    jsonRoute({
      path: '/:owner/:repo/models/prompt/pull/:pullNumber/*',
      Component: ReviewRoute,
    }),

    jsonRoute({path: '/:owner/:repo/models/:registry/:model/playground', Component: PlaygroundRoute}),
    jsonRoute({path: '/:owner/:repo/models/playground', Component: BlankSlatePlaygroundRoute}),
  ],
}))
