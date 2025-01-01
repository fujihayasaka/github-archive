import {App} from './App'
import {SecretRiskAssessmentPage} from './routes/SecretRiskAssessmentPage'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('secret-risk-assessment', () => ({
  App,
  routes: [
    jsonRoute({path: '/orgs/:org/security/metrics/secret-risk-assessment', Component: SecretRiskAssessmentPage}),
  ],
}))
