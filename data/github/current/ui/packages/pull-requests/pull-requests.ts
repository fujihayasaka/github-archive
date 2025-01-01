import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerDataRouterApp, registerNavigatorApp} from '@github-ui/react-core/register-app'
import {App} from './App'
import {PullRequestErrorState} from './components/PullRequestErrorState'
import {pullRequestsAppBuilder} from './config/app-builder'
import {CommitsEntrypoint} from './routes/Commits'
import {pullRequestsCommitsRoute} from './routes/commits-route'
import {CommitsEntrypointFuture} from './routes/CommitsFuture'
import {FilesEntrypoint} from './routes/Files'
import {CommitsRoutePath, FilesRoutePath} from './routes/route-paths'
import type {RouteObject} from 'react-router-dom'
import {pullRequestsLayoutRoute} from './routes/layout-route'
import {LayoutEntrypoint} from './routes/Layout'

// This app registers the app *twice*, under the same name: 'pull-requests'.
// Once as a navigator app, and once as a data router app.
// At runtime, a feature flag determines which app is used.

registerNavigatorApp('pull-requests', () => ({
  App,
  routes: [
    jsonRoute({path: CommitsRoutePath, Component: CommitsEntrypoint}),
    jsonRoute({path: FilesRoutePath, Component: FilesEntrypoint}),
  ],
}))

// Below is the new way to register an app. I.e with the data router.

const commitsRouteOnly: RouteObject[] = [
  pullRequestsCommitsRoute.toRoute({
    ErrorBoundary: PullRequestErrorState,
    Component: CommitsEntrypointFuture,
  }),
]

const commitsRouteWithLayout: RouteObject[] = [
  pullRequestsLayoutRoute.toRoute({
    ErrorBoundary: PullRequestErrorState,
    Component: LayoutEntrypoint,
    children: [
      pullRequestsCommitsRoute.toRoute({
        Component: CommitsEntrypointFuture,
      }),
    ],
  }),
]

export const pullRequestsApp = pullRequestsAppBuilder.createDataRouterAppFromRoutes(({isEnabled}) => {
  if (isEnabled('react_data_router_pull_requests_layout')) {
    return commitsRouteWithLayout
  } else {
    return commitsRouteOnly
  }
})

registerDataRouterApp(pullRequestsApp)
