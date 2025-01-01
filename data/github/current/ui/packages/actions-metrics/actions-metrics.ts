import {App} from './App'
import {OrgUsage} from './routes/OrgUsage'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerServices} from './common/services/service-registrations'
import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {OrgPerformance} from './routes/OrgPerformance'
import {RepoPerformance} from './routes/RepoPerformance'
import {RepoUsage} from './routes/RepoUsage'
import {EnterpriseUsage} from './routes/EnterpriseUsage'
import {EnterprisePerformance} from './routes/EnterprisePerformance'

registerServices()
registerNavigatorApp('actions-metrics', () => ({
  App,
  routes: [
    jsonRoute({
      path: '/orgs/:org/actions/metrics/usage',
      Component: OrgUsage,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/orgs/:org/actions/metrics/performance',
      Component: OrgPerformance,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/:owner/:repo/actions/metrics/usage',
      Component: RepoUsage,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/:owner/:repo/actions/metrics/performance',
      Component: RepoPerformance,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/enterprises/:slug/actions/metrics/usage',
      Component: EnterpriseUsage,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
    jsonRoute({
      path: '/enterprises/:slug/actions/metrics/performance',
      Component: EnterprisePerformance,
      transitionType: TransitionType.TRANSITION_WITHOUT_FETCH,
    }),
  ],
}))
