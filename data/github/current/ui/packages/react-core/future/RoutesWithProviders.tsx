import type {ComponentType, ReactNode} from 'react'
import {Outlet, type RouteObject} from 'react-router-dom'

import {BaseProviders} from '../BaseProviders'
import {CommonElements} from '../CommonElements'
import {RouterDevTools} from '../RouterDevTools'
import {RoutesContextProvider} from '../RoutesContextProvider'
import {AppPayloadContext} from '../use-app-payload'
import {NavigationFocusListener} from './NavigationFocusListener'
import {PublishPayload} from './PublishPayload'
import {RootAppRouteErrorElement, UnhandledRouteError} from './RouterErrorBoundary'
import {CombinedScrollRestoration} from './ScrollRestoration'
import {SoftNavLifecycleListener} from './SoftNavLifecycleListenre'
import {TitleManager} from './TitleManager'

export function routesWithProviders(
  routes: RouteObject[],
  {
    ssrError,
    appName,
    wasServerRendered,
    children,
    HydrateFallback,
    dataRouterEnabled,
    appPayload,
  }: {
    appPayload?: Record<string, unknown>
    appName: string
    ssrError: HTMLScriptElement | undefined
    wasServerRendered: boolean
    children?: ReactNode
    HydrateFallback?: ComponentType
    dataRouterEnabled: boolean
  },
): RouteObject[] {
  return [
    {
      id: `__DATA_ROUTER_ROOT__`,
      errorElement: <UnhandledRouteError appName={appName} />,
      HydrateFallback,
      element: (
        <BaseProviders appName={appName} wasServerRendered={wasServerRendered} dataRouterEnabled={dataRouterEnabled}>
          <AppPayloadContext.Provider value={appPayload}>
            <RoutesContextProvider routes={routes}>
              <Outlet />
              {children}
              <CommonElements ssrError={ssrError} />
              <SoftNavLifecycleListener />
              <NavigationFocusListener />
              <CombinedScrollRestoration />
              <PublishPayload />
              <TitleManager />
              <RouterDevTools routes={routes} />
            </RoutesContextProvider>
          </AppPayloadContext.Provider>
        </BaseProviders>
      ),
      children: [
        {
          id: `__DATA_ROUTER_APPLICATION_ROUTES__`,
          errorElement: <RootAppRouteErrorElement appName={appName} />,
          children: routes,
        },
      ],
    },
  ]
}
