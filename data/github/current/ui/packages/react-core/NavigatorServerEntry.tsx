import type {History, Location} from '@remix-run/router'
import {StaticRouter} from 'react-router-dom/server'

import type {AppComponentType} from './AppWrapper'
import {BaseProviders} from './BaseProviders'
import {CommonElements} from './CommonElements'
import type {EmbeddedData} from './embedded-data-types'
import {ErrorBoundary} from './ErrorBoundary'
import type {NavigatorAppRegistration} from './navigator-app-registry'
import {NavigatorRouter} from './NavigatorRouter'
import {useNavigator} from './use-navigator'

interface Props {
  appName: string
  history: History
  embeddedData: EmbeddedData
  routes: NavigatorAppRegistration['routes']
  App?: AppComponentType
  initialLocation: Location<unknown>
}

export function NavigatorServerEntry({appName, history, embeddedData, routes, App, initialLocation}: Props) {
  // We create our "app" here. The app is a state machine that lets you dispatch a history update
  // and gives you a resolved location (after e.g., loading, redirects, etc.)
  const [{location, error, routeStateMap, appPayload, navigateOnError}] = useNavigator({
    initialLocation,
    appName,
    embeddedData,
    routes,
  })

  return (
    <BaseProviders appName={appName} wasServerRendered dataRouterEnabled={false}>
      <ErrorBoundary>
        <NavigatorRouter
          App={App}
          appPayload={appPayload}
          error={error}
          history={history}
          location={location}
          navigateOnError={navigateOnError}
          Router={StaticRouter}
          routes={routes}
          routeStateMap={routeStateMap}
        >
          <CommonElements />
        </NavigatorRouter>
      </ErrorBoundary>
    </BaseProviders>
  )
}
