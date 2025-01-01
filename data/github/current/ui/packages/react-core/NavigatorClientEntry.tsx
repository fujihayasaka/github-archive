import {useLayoutEffect} from '@github-ui/use-layout-effect'
import type {History, Location} from '@remix-run/router'
import {Router} from 'react-router-dom'

import type {AppComponentType} from './AppWrapper'
import {BaseProviders} from './BaseProviders'
import {CommonElements} from './CommonElements'
import type {EmbeddedData} from './embedded-data-types'
import {ErrorBoundary} from './ErrorBoundary'
import type {NavigatorAppRegistration} from './navigator-app-registry'
import {NavigatorRouter} from './NavigatorRouter'
import {useNavigationFocus} from './use-navigation-focus'
import {useNavigator} from './use-navigator'
import {installScrollRestoration, useScrollRestoration} from './use-scroll-restoration'
import {useSoftNavLifecycle} from './use-soft-nav-lifecycle'
import {useTitleManager} from './use-title-manager'

installScrollRestoration()

interface Props {
  appName: string
  initialLocation: Location<unknown>
  embeddedData: EmbeddedData
  routes: NavigatorAppRegistration['routes']
  App?: AppComponentType
  wasServerRendered: boolean
  ssrError?: HTMLScriptElement
  history: History
  onError?: (error: Error) => void
}

export function NavigatorClientEntry({
  appName,
  initialLocation,
  history,
  embeddedData,
  routes,
  App,
  wasServerRendered,
  ssrError,
  onError,
}: Props) {
  // We create our "app" here. The app is a state machine that lets you dispatch a history update
  // and gives you a resolved location (after e.g., loading, redirects, etc.)
  const [{location, error, routeStateMap, appPayload, navigateOnError, isLoading}, {handleHistoryUpdate}] =
    useNavigator({
      initialLocation,
      appName,
      embeddedData,
      routes,
    })

  useTitleManager(routeStateMap[location.key]!, error, location)
  useNavigationFocus(isLoading, location)
  useSoftNavLifecycle(location, isLoading, error)
  useScrollRestoration()

  // When we get a history update, we send it to our app via handleHistoryUpdate
  // Note, we only want this to run in the browser to avoid SSR warnings about useLayoutEffect
  useLayoutEffect(() => {
    const unlisten = history.listen(handleHistoryUpdate)
    return unlisten
  }, [history, handleHistoryUpdate])

  return (
    <BaseProviders appName={appName} wasServerRendered={wasServerRendered} dataRouterEnabled={false}>
      <ErrorBoundary onError={onError} critical>
        <NavigatorRouter
          App={App}
          appPayload={appPayload}
          error={error}
          history={history}
          location={location}
          navigateOnError={navigateOnError}
          Router={Router}
          routes={routes}
          routeStateMap={routeStateMap}
        >
          <CommonElements ssrError={ssrError} />
        </NavigatorRouter>
      </ErrorBoundary>
    </BaseProviders>
  )
}
