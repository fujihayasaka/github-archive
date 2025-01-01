import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {pushProtectionPatternConfigurationsAppBuilder} from './config/app-builder'

import {patternConfigsPageRoute} from './routes/pattern-configs-page-route'
import {PatternConfigsPage} from './routes/PatternConfigsPage'

export const pushProtectionPatternConfigurationsApp =
  pushProtectionPatternConfigurationsAppBuilder.createDataRouterAppFromRoutes([
    patternConfigsPageRoute.toRoute({Component: PatternConfigsPage}),
  ])
registerDataRouterApp(pushProtectionPatternConfigurationsApp)
