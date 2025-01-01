import {App} from './App'
import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {Index} from './routes/Index/Page'
import {New} from './routes/New/Page'
import {Assessing} from './routes/Assessing/Page'
import {Assessment} from './routes/Assessment/Page'
import {Training} from './routes/Training/Page'

registerNavigatorApp('copilot-custom-models-ga-ui', () => ({
  App,
  routes: [
    jsonRoute({
      path: '/organizations/:org/custom_models_ga_ui',
      Component: Index,
      transitionType: TransitionType.FETCH_THEN_TRANSITION,
    }),
    jsonRoute({
      path: '/organizations/:org/custom_models_ga_ui/new',
      Component: New,
      transitionType: TransitionType.FETCH_THEN_TRANSITION,
    }),
    jsonRoute({
      path: '/organizations/:org/custom_models_ga_ui/assessing',
      Component: Assessing,
      transitionType: TransitionType.FETCH_THEN_TRANSITION,
    }),
    jsonRoute({
      path: '/organizations/:org/custom_models_ga_ui/assessment',
      Component: Assessment,
      transitionType: TransitionType.FETCH_THEN_TRANSITION,
    }),
    jsonRoute({
      path: '/organizations/:org/custom_models_ga_ui/training',
      Component: Training,
      transitionType: TransitionType.FETCH_THEN_TRANSITION,
    }),
  ],
}))
