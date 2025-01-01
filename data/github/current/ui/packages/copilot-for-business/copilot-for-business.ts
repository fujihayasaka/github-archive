import React from 'react'

import {App} from './App'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {jsonRoute} from '@github-ui/react-core/json-route'

const PoliciesPage = React.lazy(() => import(/* webpackPreload: true */ './routes/Policies'))
const ModelsPage = React.lazy(() => import(/* webpackPreload: true */ './routes/Models'))
const SeatManagementPage = React.lazy(() => import(/* webpackPreload: true */ './routes/SeatManagement'))
const StandaloneSeatManagementPage = React.lazy(
  () => import(/* webpackPreload: true */ './routes/StandaloneSeatManagement'),
)

registerNavigatorApp('copilot-for-business', () => ({
  App,
  routes: [
    jsonRoute({path: '/organizations/:org/settings/copilot/seat_management', Component: SeatManagementPage}),
    jsonRoute({path: '/organizations/:org/settings/copilot/policies', Component: PoliciesPage}),
    jsonRoute({path: '/organizations/:org/settings/copilot/models', Component: ModelsPage}),
    jsonRoute({
      path: '/enterprises/:slug/enterprise_licensing/copilot/seat_management',
      Component: StandaloneSeatManagementPage,
    }),
  ],
}))
