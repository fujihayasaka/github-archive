import './copilot-immersive-v1.module.css'

import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import {CopilotImmersive} from './routes/CopilotImmersive'

registerNavigatorApp('copilot-immersive-v1', () => ({
  App,
  routes: [
    jsonRoute({path: '/copilot', Component: CopilotImmersive, transitionType: TransitionType.TRANSITION_WITHOUT_FETCH}),
    jsonRoute({
      path: '/copilot/c/:threadID',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({path: '/copilot/d/:docsetName', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/r/:owner/:repository', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/share/:threadID', Component: CopilotImmersive}),
    jsonRoute({
      path: '/copilot/pipes',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/copilot/workbench',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({path: '/copilot/spaces', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/spaces/:spaceID', Component: CopilotImmersive}),
  ],
}))
