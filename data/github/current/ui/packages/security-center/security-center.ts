import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import {CodeScanningReport} from './routes/CodeScanningReport'
import {DependabotReport} from './routes/DependabotReport'
import {EnablementTrendsReport} from './routes/EnablementTrendsReport'
import {Overview} from './routes/Overview'
import {SecretScanningReport} from './routes/SecretScanningReport'

registerNavigatorApp('security-center', () => ({
  App,
  routes: [
    // enterprise
    jsonRoute({path: '/enterprises/:business/security/overview', Component: Overview}),
    jsonRoute({path: '/enterprises/:business/security/metrics/enablement', Component: EnablementTrendsReport}),
    jsonRoute({path: '/enterprises/:business/security/metrics/codeql', Component: CodeScanningReport}),
    jsonRoute({path: '/enterprises/:business/security/metrics/secret-scanning', Component: SecretScanningReport}),

    // organization
    jsonRoute({path: '/orgs/:org/security/overview', Component: Overview}),
    jsonRoute({path: '/orgs/:org/security/metrics/enablement', Component: EnablementTrendsReport}),
    jsonRoute({path: '/orgs/:org/security/metrics/codeql', Component: CodeScanningReport}),
    jsonRoute({path: '/orgs/:org/security/metrics/secret-scanning', Component: SecretScanningReport}),
    jsonRoute({path: '/orgs/:org/security/metrics/dependabot', Component: DependabotReport}),
  ],
}))
