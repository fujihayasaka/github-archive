import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerReactAppFactory} from '@github-ui/react-core/register-app'

import {App} from './App'

import {BoomTown} from './routes/BoomTown'
import {CopilotExtensionsIndex} from './routes/features/CopilotExtensionsIndex/CopilotExtensionsIndex'
import {CopilotIndex} from './routes/CopilotIndex'
import {CopilotPlansIndex} from './routes/copilot/PlansIndex'
import {DiversityIndex} from './routes/about/diversity/DiversityIndex'
import {EnterpriseAdvancedSecurityIndex} from './routes/enterprise/advanced-security/Index'
import {FeaturesIndex} from './routes/features/FeaturesIndex'
import {Home} from './routes/home/Index'
import {ShowPage} from './routes/ShowPage'
import {ThankYouPage} from './routes/ThankYouPage'
import EnterpriseIndex from './routes/enterprise/Index'
import FeaturesActionsIndex from './routes/features/actions/Index'
import FeaturesCodeReviewIndex from './routes/features/code-review/Index'
import FeaturesCodeSearchIndex from './routes/features/code-search/Index'
import FeaturesCodespacesIndex from './routes/features/codespaces/Index'
import FeaturesDiscussionsIndex from './routes/features/discussions/Index'
import FeaturesIssuesIndex from './routes/features/issues/Index'

registerReactAppFactory('landing-pages', () => ({
  App,
  routes: [
    jsonRoute({path: '/about/diversity', Component: DiversityIndex}),
    jsonRoute({path: '/contact-sales/thank-you', Component: ThankYouPage}),
    jsonRoute({path: '/enterprise', Component: EnterpriseIndex}),
    jsonRoute({path: '/enterprise/advanced-security', Component: EnterpriseAdvancedSecurityIndex}),
    jsonRoute({path: '/enterprise/contact/thanks', Component: ThankYouPage}),
    jsonRoute({path: '/features', Component: FeaturesIndex}),
    jsonRoute({path: '/features/actions', Component: FeaturesActionsIndex}),
    jsonRoute({path: '/features/code-review', Component: FeaturesCodeReviewIndex}),
    jsonRoute({path: '/features/code-search', Component: FeaturesCodeSearchIndex}),
    jsonRoute({path: '/features/codespaces', Component: FeaturesCodespacesIndex}),
    jsonRoute({path: '/features/copilot', Component: CopilotIndex}),
    jsonRoute({path: '/features/copilot/extensions', Component: CopilotExtensionsIndex}),
    jsonRoute({path: '/features/copilot/plans', Component: CopilotPlansIndex}),
    jsonRoute({path: '/features/discussions', Component: FeaturesDiscussionsIndex}),
    jsonRoute({path: '/features/issues', Component: FeaturesIssuesIndex}),
    jsonRoute({path: '/home', Component: Home}),
    jsonRoute({path: '/', Component: Home}),

    /**
     * We use this route to exercise error handling and exception reporting.
     * in the app. The BoomTown component simply throws an error when it renders.
     */
    jsonRoute({path: '/contentful-lp-tests/boomtown', Component: BoomTown}),

    jsonRoute({path: '*', Component: ShowPage}),
  ],
}))
