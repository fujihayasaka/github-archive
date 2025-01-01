import type {ComponentType, ReactNode} from 'react'
import {Outlet, type RouteObject} from 'react-router-dom'
import {BaseProviders} from '../BaseProviders'
import {CommonElements} from '../CommonElements'
import {RoutesContextProvider} from '../RoutesContextProvider'
import {AppPayloadContext} from '../use-app-payload'
import {NavigationFocusListener} from './NavigationFocusListener'
import {PublishPayload} from './PublishPayload'
import {ResponseErrorElement, RouterErrorBoundary} from './RouterErrorBoundary'
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
      errorElement: <RouterErrorBoundary />,
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
            </RoutesContextProvider>
          </AppPayloadContext.Provider>
        </BaseProviders>
      ),
      children: [
        {
          errorElement: <ResponseErrorElement />,
          children: routes,
        },
      ],
    },
  ]
}
