import {App} from './App'
import {BusinessTeamsListView} from './routes/BusinessTeamsListView'
import {BusinessTeamsItemView} from './routes/BusinessTeamsItemView'
import {BusinessTeamsCreateEditView} from './routes/BusinessTeamsCreateEditView'
import {registerReactAppFactory} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

registerReactAppFactory('business-teams', () => ({
  App,
  routes: [
    jsonRoute({path: '/enterprises/:slug/teams', Component: BusinessTeamsListView}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug', Component: BusinessTeamsItemView}),
    jsonRoute({path: '/enterprises/:slug/new_team', Component: BusinessTeamsCreateEditView}),
    jsonRoute({path: '/enterprises/:slug/teams/:team_slug/edit', Component: BusinessTeamsCreateEditView}),
  ],
}))
