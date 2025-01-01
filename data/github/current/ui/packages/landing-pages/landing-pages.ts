import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {isFeatureEnabled} from '@github-ui/feature-flags'

import {App} from './App'

import {BoomTown} from './routes/BoomTown'
import {DiversityIndex} from './routes/about/diversity/DiversityIndex'
import {Home} from './routes/home/Index'
import {ShowPage} from './routes/ShowPage'
import {ThankYouPage} from './routes/ThankYouPage'
import EnterpriseIndex from './routes/enterprise/Index'
import {EnterpriseAdvancedSecurityIndex} from './routes/enterprise/advanced-security/Index'
import {FeaturesIndex} from './routes/features/FeaturesIndex'
import FeaturesCopilotIndex from './routes/features/copilot/Index'
import FeaturesCopilotExtensionsIndex from './routes/features/copilot/extensions/Index'
import FeaturesCopilotPlansIndex from './routes/features/copilot/plans/Index'
import SecurityAdvancedSecurityIndex from './routes/security/advanced-security/Index'
import SecurityPlansIndex from './routes/security/plans/Index'

registerNavigatorApp('landing-pages', () => ({
  App,
  routes: [
    jsonRoute({path: '/about/diversity', Component: DiversityIndex}),
    jsonRoute({path: '/contact-sales/thank-you', Component: ThankYouPage}),
    jsonRoute({
      path: '/enterprise',
      Component: isFeatureEnabled('contentful_lp_enterprise') ? ShowPage : EnterpriseIndex,
    }),
    jsonRoute({path: '/enterprise/advanced-security', Component: EnterpriseAdvancedSecurityIndex}),
    jsonRoute({path: '/enterprise/contact/thanks', Component: ThankYouPage}),
    jsonRoute({
      path: '/features',
      Component: isFeatureEnabled('contentful_lp_flex_features') ? ShowPage : FeaturesIndex,
    }),
    jsonRoute({path: '/features/copilot', Component: FeaturesCopilotIndex}),
    jsonRoute({
      path: '/features/copilot/extensions',
      Component: isFeatureEnabled('contentful_lp_copilot_extensions') ? ShowPage : FeaturesCopilotExtensionsIndex,
    }),
    jsonRoute({path: '/features/copilot/plans', Component: FeaturesCopilotPlansIndex}),
    jsonRoute({path: '/home', Component: Home}),
    jsonRoute({path: '/security/advanced-security', Component: SecurityAdvancedSecurityIndex}),
    jsonRoute({path: '/security/plans', Component: SecurityPlansIndex}),

    /**
     * We use this route to exercise error handling and exception reporting.
     * in the app. The BoomTown component simply throws an error when it renders.
     */
    jsonRoute({path: '/contentful-lp-tests/boomtown', Component: BoomTown}),

    jsonRoute({path: '*', Component: ShowPage}),
  ],
}))
