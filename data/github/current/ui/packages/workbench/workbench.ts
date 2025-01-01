import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import {Workbench} from './routes/Workbench'

registerNavigatorApp('workbench', () => ({
  App,
  routes: [
    jsonRoute({path: `/copilot/spark/:spark_id`, Component: Workbench}),
    jsonRoute({path: `/copilot/spark/:spark_id/file/:path/*`, Component: Workbench}),

    jsonRoute({path: `/:owner/:repo/workbench/:pr_number/edit`, Component: Workbench}),
    jsonRoute({path: `/:owner/:repo/workbench/:pr_number/edit/new`, Component: Workbench}),
    jsonRoute({path: `/:owner/:repo/workbench/:pr_number/edit/file/:path/*`, Component: Workbench}),
  ],
}))
