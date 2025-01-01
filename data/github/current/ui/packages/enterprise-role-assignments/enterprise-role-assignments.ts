import {App} from './App'
import {EnterpriseRoleAssignments} from './routes/EnterpriseRoleAssignments'
import {registerReactAppFactory} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerReactAppFactory('enterprise-role-assignments', () => ({
  App,
  routes: [
    jsonRoute({path: '/enterprises/:business/enterprise_role_assignments', Component: EnterpriseRoleAssignments}),
  ],
}))
