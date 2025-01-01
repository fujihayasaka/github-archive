import {App} from './App'
import {NewExemptionRequestPage} from './routes/NewExemptionRequestPage'
import {ExemptionRequestPage} from './routes/ExemptionRequestPage'
import {BypassRequestsPage} from './routes/BypassRequestsPage'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('delegated-bypass', () => ({
  App,
  routes: [
    jsonRoute({path: '/:owner/:repo/exemptions/new/:exemptionHashId', Component: NewExemptionRequestPage}),
    jsonRoute({path: '/:owner/:repo/exemptions/:exemptionHashId', Component: ExemptionRequestPage}),
    jsonRoute({path: '/:owner/:repo/settings/rules/bypass_requests', Component: BypassRequestsPage}),
    jsonRoute({
      path: '/:owner/:repo/secret_scanning/exemptions/new/:exemptionHashId',
      Component: NewExemptionRequestPage,
    }),
    jsonRoute({path: '/:owner/:repo/secret_scanning/exemptions/:exemptionHashId', Component: ExemptionRequestPage}),
    jsonRoute({path: '/:owner/:repo/security/secret_scanning/bypass_requests', Component: BypassRequestsPage}),
    jsonRoute({path: '/orgs/:org/security/bypass-requests/secret-scanning', Component: BypassRequestsPage}),
    jsonRoute({path: '/orgs/:org/security/bypass-requests/code-scanning', Component: BypassRequestsPage}),
    jsonRoute({
      path: '/enterprises/:enterprise/settings/policies/:policy_type/bypass_requests',
      Component: BypassRequestsPage,
    }),
    jsonRoute({path: '/:owner/:repo/secret_scanning/closure_requests/:number', Component: ExemptionRequestPage}),
    jsonRoute({path: '/orgs/:org/security/closure-requests/secret-scanning', Component: BypassRequestsPage}),
    jsonRoute({
      path: '/stafftools/repositories/:owner/:repo/exemptions/:exemptionHashId',
      Component: ExemptionRequestPage,
    }),
    jsonRoute({
      path: '/stafftools/repositories/:owner/:repo/bypass_requests',
      Component: BypassRequestsPage,
    }),
    jsonRoute({
      path: '/stafftools/users/:org/bypass_requests',
      Component: BypassRequestsPage,
    }),
    jsonRoute({path: '/stafftools/enterprises/:enterprise/bypass_requests', Component: BypassRequestsPage}),
  ],
}))
