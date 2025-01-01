import {App} from './App'
import {EnterpriseTeamManagement} from './routes/EnterpriseTeamManagement'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerNavigatorApp('enterprise-team-management', () => ({
  App,
  routes: [
    jsonRoute({path: '/enterprises/:slug/new_team', Component: EnterpriseTeamManagement}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug/edit', Component: EnterpriseTeamManagement}),
  ],
}))
