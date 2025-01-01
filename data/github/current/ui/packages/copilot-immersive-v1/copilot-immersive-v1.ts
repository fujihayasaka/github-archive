// eslint-disable-next-line primer-react/enforce-css-module-default-import
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
      path: '/copilot/loop/share',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/copilot/loops',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/copilot/l/:loopID',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/copilot/workbench',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/copilot/spark',
      Component: CopilotImmersive,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({path: '/copilot/spaces', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/spaces/:spaceID', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/spaces/:owner/:spaceNumber', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/spaces/:owner/:spaceNumber/edit', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/spaces/:spaceID/edit', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/spaces/new', Component: CopilotImmersive}),
    jsonRoute({path: '/copilot/agents', Component: CopilotImmersive}),
  ],
}))
