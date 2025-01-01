import {TransitionType} from '@github-ui/react-core/app-routing-types'
import {jsonRoute} from '@github-ui/react-core/json-route'
import {registerNavigatorApp} from '@github-ui/react-core/register-app'
import {relayEnvironmentWithMissingFieldHandlerForNode} from '@github-ui/relay-environment'
import {relayRoute} from '@github-ui/relay-route'
import {createElement} from 'react'
import {Fragment} from 'react/jsx-runtime'

import {App} from './App'
import {CssModules} from './routes/CssModules/CssModules'
import {FilterPage} from './routes/Filter'
import {GlobalNavigationPage} from './routes/GlobalNavigation'
import {IndexPage} from './routes/Index'
import RelaySandboxPageQuery$parameters from './routes/RelaySandboxPage/__generated__/RelaySandboxPageQuery$parameters'
import {RelaySandboxPage} from './routes/RelaySandboxPage/RelaySandboxPage'
import {ShowPage} from './routes/Show'
import {SSRErrorPage} from './routes/SSRError'
import {StaticAsset} from './routes/StaticAsset'
import {UIDeploys} from './routes/UIDeploys'
import {SandboxLayoutWithOutlet} from './SandboxLayout'

registerNavigatorApp('react-sandbox', () => {
  const relayEnvironment = relayEnvironmentWithMissingFieldHandlerForNode()
  return {
    App,
    routes: [
      jsonRoute({
        path: '/_react_sandbox',
        Component: SandboxLayoutWithOutlet,
        transitionType: TransitionType.TRANSITION_WHILE_FETCHING,
        children: [
          {
            path: '/_react_sandbox',
            Component: IndexPage,
          },
          {
            path: '/_react_sandbox/ssr-error',
            Component: SSRErrorPage,
          },
          {
            path: '/_react_sandbox/:sandbox_id',
            Component: ShowPage,
          },
          {path: '/_react_sandbox/filter', Component: FilterPage},
          {path: '/_react_sandbox/css-modules', Component: CssModules},
          {path: '/_react_sandbox/static-asset', Component: StaticAsset},
          {path: '/_react_sandbox/ui-deploys', Component: UIDeploys},
          {path: '/_react_sandbox/global-navigation', Component: GlobalNavigationPage},
        ],
      }),
      relayRoute({
        path: '/_react_sandbox/relay',
        componentLoader: async () => {
          return RelaySandboxPage
        },
        Component: RelaySandboxPage,
        resourceName: 'valid resource name',
        queryConfigs: {
          relaySandboxPage: {
            concreteRequest: RelaySandboxPageQuery$parameters,
          },
        },
        title: 'title',
        relayEnvironment,
        fallback: createElement(Fragment),
      }),
    ],
  }
})
