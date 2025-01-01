import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
// eslint-disable-next-line no-restricted-imports
import {App} from '@github-ui/pull-requests/App'
// eslint-disable-next-line no-restricted-imports
import {FilesEntrypoint} from '@github-ui/pull-requests/FilesEntrypoint'

registerNavigatorApp('pull-request-files', () => ({
  App,
  routes: [
    jsonRoute({path: '/:owner/:repo/pull/:pr_number/files', Component: FilesEntrypoint}),
    jsonRoute({path: '/:owner/:repo/pull/:pr_number/files/:range', Component: FilesEntrypoint}),
  ],
}))
