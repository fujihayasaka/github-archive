import {App} from './App'
import {EnterpriseRoleAssignments} from './routes/EnterpriseRoleAssignments'
import {StafftoolsEnterpriseRoleAssignments} from './routes/StafftoolsEnterpriseRoleAssignments'
import {NewEnterpriseRoleAssignment} from './routes/NewEnterpriseRoleAssignment'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {NewOrgRoleAssignment} from './routes/NewOrgRoleAssignments'
import {OrgRoleAssignments} from './routes/OrgRoleAssignments'

registerNavigatorApp('enterprise-role-assignments', () => ({
  App,
  routes: [
    jsonRoute({path: '/enterprises/:business/enterprise_role_assignments', Component: EnterpriseRoleAssignments}),
    jsonRoute({path: '/enterprises/:business/enterprise_role_assignments/new', Component: NewEnterpriseRoleAssignment}),
    jsonRoute({path: '/organizations/:organization_id/settings/org_role_assignments', Component: OrgRoleAssignments}),
    jsonRoute({
      path: '/organizations/:organization_id/settings/org_role_assignments/new',
      Component: NewOrgRoleAssignment,
    }),
    jsonRoute({
      path: '/stafftools/enterprises/:business/custom_roles/enterprise_role_assignments',
      Component: StafftoolsEnterpriseRoleAssignments,
    }),
  ],
}))
