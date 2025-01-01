import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import type {InitialEntry, Router} from '@remix-run/router'
import type {FC, ProfilerOnRenderCallback} from 'react'
import {createMemoryRouter, RouterProvider} from 'react-router-dom'

import type {EmbeddedData} from '../../embedded-data-types'
import {Profiler, ProfilerProvider} from '../../ProfilerContext'
import {v7_routeProviderFutureFlags, v7_routerFutureFlags} from '../../react-router-future-flags'
import {applyRouterNavigateOverride} from '../apply-router-navigate-override'
import type {DataRouterApplication} from '../data-router-application'
import {routesWithProviders} from '../RoutesWithProviders'

export type RouterOpts = Pick<
  NonNullable<Parameters<typeof createMemoryRouter>[1]>,
  'initialEntries' | 'initialIndex' | 'hydrationData'
>

export type DataRouterAppWrapperRouterProps = {
  appPayload?: Record<string, unknown>
  embeddedData?: EmbeddedData
  profiler?: {
    onRender: ProfilerOnRenderCallback
  }
}

export type DataRouterAppWrapperProps = DataRouterAppWrapperRouterProps &
  RouterOpts & {
    app: DataRouterApplication<string>
    router: Router
  }

export function DefaultHydrateFallback() {
  return <div>loading...</div>
}

export const defaultProfiler: {onRender: ProfilerOnRenderCallback} = {
  onRender: () => {},
}

export const DataRouterAppWrapper: FC<DataRouterAppWrapperProps> = ({app, router, profiler = defaultProfiler}) => {
  applyRouterNavigateOverride(router)

  return (
    <AliveTestProvider>
      <ProfilerProvider isDataRouterEnabled appName={app.name} onRender={profiler.onRender}>
        <Profiler id={app.name}>
          <RouterProvider router={router} future={v7_routeProviderFutureFlags} />
        </Profiler>
      </ProfilerProvider>
    </AliveTestProvider>
  )
}

interface CreateMemoryDataRouterOptions {
  app: DataRouterApplication<string>
  initialEntries: PathOrRouterOptions
  embeddedData?: EmbeddedData
  appPayload?: Record<string, unknown>
}

export function createMemoryDataRouter({app, initialEntries, embeddedData, appPayload}: CreateMemoryDataRouterOptions) {
  // DataRouter deletes keys from `embeddedData` read from the DOM to avoid re-loading it on subsequent renders, but
  // that's not relevant to tests, so we clone it here to avoid unexpectedly modifying the mock data.
  const {routes} = app.registration(embeddedData ? clone({embeddedData}) : undefined)

  const router = createMemoryRouter(
    routesWithProviders(routes, {
      appPayload: appPayload ?? embeddedData?.appPayload,
      ssrError: undefined,
      appName: app.name,
      wasServerRendered: false,
      HydrateFallback: DefaultHydrateFallback,
      dataRouterEnabled: true,
    }),
    {
      ...getRouterOptions(initialEntries),
      future: v7_routerFutureFlags,
    },
  )
  return router
}

type RouterOptionsWithEntries = {initialEntries: InitialEntry[] | undefined; initialIndex?: number | undefined}
export type PathOrRouterOptions = string | string[] | RouterOptionsWithEntries

export function getRouterOptions(pathOrRouterOptions: PathOrRouterOptions): RouterOptionsWithEntries {
  if (Array.isArray(pathOrRouterOptions)) {
    return {
      initialEntries: pathOrRouterOptions,
    }
  }

  if (typeof pathOrRouterOptions === 'string') {
    return {
      initialEntries: [pathOrRouterOptions],
    }
  }

  return pathOrRouterOptions
}

/**
 * Handle the case where structuredClone is not available
 * I was seeing this in Jest tests running in VS Code (despite being in Node 23)
 */
function clone(target: unknown) {
  if (typeof structuredClone === 'function') {
    return structuredClone(target)
  }
  return JSON.parse(JSON.stringify(target))
}
