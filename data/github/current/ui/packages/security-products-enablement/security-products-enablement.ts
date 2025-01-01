import App from './App'
import OrganizationSettingsSecurityProducts from './routes/OrganizationSettingsSecurityProducts'
import SecurityConfiguration from './routes/SecurityConfiguration'
import EnterpriseSettings from './routes/EnterpriseSettings'
import RepositorySettings from './routes/RepositorySettings'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import UserSettings from './routes/UserSettings'

registerNavigatorApp('security-products-enablement', () => ({
  App,
  routes: [
    jsonRoute({
      path: '/organizations/:organization/settings/security_products',
      Component: OrganizationSettingsSecurityProducts,
    }),
    jsonRoute({
      path: '/organizations/:organization/settings/security_products/configurations/new',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/organizations/:organization/settings/security_products/configurations/edit/:id',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/organizations/:organization/settings/security_products/configurations/view/:id',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/enterprises/:enterprise/settings/security_analysis',
      Component: EnterpriseSettings,
    }),
    jsonRoute({
      path: '/enterprises/:enterprise/settings/security_analysis/configurations/new',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/enterprises/:enterprise/settings/security_analysis/configurations/:id/edit',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/enterprises/:enterprise/settings/security_analysis/configurations/:id/view',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/users/settings/security_products',
      Component: UserSettings,
    }),
    jsonRoute({
      path: '/users/settings/security_products/configurations/new',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/users/settings/security_products/configurations/edit/:id',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/users/settings/security_products/configurations/view/:id',
      Component: SecurityConfiguration,
    }),
    jsonRoute({
      path: '/:organization/:repository/settings/security_analysis',
      Component: RepositorySettings,
    }),
  ],
}))
