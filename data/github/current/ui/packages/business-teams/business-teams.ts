import {App} from './App'
import {BusinessTeamsListView} from './routes/BusinessTeamsListView'
import {BusinessTeamMembersView} from './routes/BusinessTeamMembersView'
import {BusinessTeamRolesView} from './routes/BusinessTeamRolesView'
import {BusinessTeamsCreateEditView} from './routes/BusinessTeamsCreateEditView'
import {StafftoolsBusinessTeamsListView} from './routes/stafftools/StafftoolsBusinessTeamsListView'
import {StafftoolsBusinessTeamsItemView} from './routes/stafftools/StafftoolsBusinessTeamsItemView'
import {StafftoolsBusinessTeamMembersView} from './routes/stafftools/StafftoolsBusinessTeamMembersView'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {BusinessTeamOrganizationsView} from './routes/BusinessTeamOrganizationsView'

registerNavigatorApp('business-teams', () => ({
  App,
  routes: [
    jsonRoute({path: '/enterprises/:slug/teams', Component: BusinessTeamsListView}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug', Component: BusinessTeamMembersView}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug/members', Component: BusinessTeamMembersView}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug/organizations', Component: BusinessTeamOrganizationsView}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug/roles', Component: BusinessTeamRolesView}),
    jsonRoute({path: '/enterprises/:slug/new_team', Component: BusinessTeamsCreateEditView}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug/edit', Component: BusinessTeamsCreateEditView}),
    jsonRoute({path: '/stafftools/enterprises/:slug/enterprise_teams', Component: StafftoolsBusinessTeamsListView}),
    jsonRoute({path: '/stafftools/enterprises/:slug/enterprise_teams/:id', Component: StafftoolsBusinessTeamsItemView}),
    jsonRoute({
      path: '/stafftools/enterprises/:slug/enterprise_teams/:id/members',
      Component: StafftoolsBusinessTeamMembersView,
    }),
  ],
}))
