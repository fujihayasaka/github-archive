import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'

import {App} from './App'
import {WorkspaceEditor} from './routes/WorkspaceEditor'
import {EDITOR_PATH} from './utilities/urls'

registerNavigatorApp('workspace-editor', () => ({
  App,
  routes: [
    jsonRoute({path: `/:owner/:repo/pull/:pr_number/${EDITOR_PATH}`, Component: WorkspaceEditor}),
    jsonRoute({path: `/:owner/:repo/pull/:pr_number/${EDITOR_PATH}/new`, Component: WorkspaceEditor}),
    jsonRoute({path: `/:owner/:repo/pull/:pr_number/${EDITOR_PATH}/file/:path/*`, Component: WorkspaceEditor}),
  ],
}))
