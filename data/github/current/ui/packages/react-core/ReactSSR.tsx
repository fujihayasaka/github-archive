import './public-path'
// eslint-disable-next-line no-restricted-imports
import {reactNavigatorAppSyncRegistry, reactDataRouterAppSyncRegistry} from './register-app.server'
// eslint-disable-next-line no-restricted-imports
import {reactPartials} from './register-partial.server'

import {type ClientEnvironment, setClientEnvForSsr} from '@github-ui/client-env'
import {setLocation, ssrSafeLocation} from '@github-ui/ssr-utils'
import {createMemoryHistory} from '@remix-run/router'
import {renderToString} from 'react-dom/server'
import {createStaticHandler, createStaticRouter, StaticRouterProvider} from 'react-router-dom/server'
import {ServerStyleSheet} from 'styled-components'
import {NavigatorServerEntry} from './NavigatorServerEntry'
import {PartialEntry} from './PartialEntry'
import type {EmbeddedData, EmbeddedPartialData} from './embedded-data-types'
import {routesWithProviders} from './future/RoutesWithProviders'
import type {DataRouterAppRegistrationObject} from './future/data-router-app-registry'
import {type ColorModeOptions, setColorModeOptions} from './use-color-modes'
import {getQueryClient} from './query-client'

interface BaseRequest {
  name: string
  url: string
  clientEnv: ClientEnvironment | null
  colorModes: ColorModeOptions
  data_router_enabled?: boolean
}

export interface AppRenderRequest extends BaseRequest {
  path: string
  data: EmbeddedData
}

export interface PartialRenderRequest extends BaseRequest {
  data: EmbeddedPartialData
}

function getLocationPartsFromPath(path: string) {
  const {pathname, search, hash} = new URL(
    path,
    // we fallback to github.com, if a location is not set, but this shouldn't be relied on
    ssrSafeLocation.origin || 'https://github.com',
  )

  return {
    pathname,
    search,
    hash,
  } as const
}

async function getDataRouterAppEntry({
  app,
  path,
  name,
  data,
}: {
  app: DataRouterAppRegistrationObject
  name: string
  path: string
  data: EmbeddedData
}) {
  const register = app.registration({embeddedData: data})

  const routes = routesWithProviders(register.routes, {
    appPayload: data.appPayload,
    ssrError: undefined,
    appName: name,
    wasServerRendered: true,
    dataRouterEnabled: true,
  })
  const {dataRoutes, query} = createStaticHandler(routes, {})
  const ctx = await query(
    // this approximates a Request object, which isn't yet supported. We'll update this to a Request once it is
    {
      url: new URL(path, ssrSafeLocation.origin || 'https://github.com'),
      method: 'GET',
      signal: new AbortController().signal,
    } as unknown as Request,
  )

  if (!('matches' in ctx)) {
    // If `query` returns a Response, we should redirect instead - this would be a loader redirecting
    // We don't support this, as we should redirect in rails directly
    throw new Error('Loader redirects via throwing a Response is not currently supported.')
  }

  const router = createStaticRouter(dataRoutes, ctx)

  return <StaticRouterProvider router={router} context={ctx} hydrate={false} />
}

async function getAppEntry({name, path, data, data_router_enabled}: AppRenderRequest) {
  if (data_router_enabled) {
    const app = reactDataRouterAppSyncRegistry.get(name)
    if (!app) {
      throw new Error(`Unknown data router app ${name}`)
    }
    return getDataRouterAppEntry({app, name, path, data})
  }

  const app = reactNavigatorAppSyncRegistry.get(name)
  if (!app) {
    throw new Error(`Unknown navigator app ${name}`)
  }

  const {App, routes} = app.registration()

  // Initial path is set by ruby. Fragments are not sent to the server.
  const {pathname, search, hash} = getLocationPartsFromPath(path)
  const history = createMemoryHistory({initialEntries: [{pathname, search, hash}], v5Compat: true})
  const {key, state} = history.location
  const initialLocation = {
    pathname,
    search,
    hash,
    key,
    state,
  }

  return (
    <NavigatorServerEntry
      appName={name}
      embeddedData={data}
      routes={routes}
      App={App}
      initialLocation={initialLocation}
      history={history}
    />
  )
}

function getPartialEntry({name, data}: PartialRenderRequest, url: string) {
  const partial = reactPartials.get(name)

  if (!partial) {
    throw new Error(`Unknown partial ${name}`)
  }

  const {pathname, search, hash} = getLocationPartsFromPath(url)
  const {Component} = partial

  const history = createMemoryHistory({initialEntries: [{pathname, search, hash}]})
  return (
    <PartialEntry history={history} partialName={name} embeddedData={data} Component={Component} wasServerRendered />
  )
}

export async function handleRequest(request: AppRenderRequest | PartialRenderRequest) {
  // always ensure we have a _clean_ queryClient on the server
  getQueryClient().clear()
  // Ensure the correct color mode options are applied
  const {colorModes, url} = request
  setColorModeOptions(colorModes)
  setLocation(url)
  setClientEnvForSsr(request.clientEnv || undefined)

  // Get the entry node, based on the request type
  const entry = 'path' in request ? await getAppEntry(request) : getPartialEntry(request, url)

  // Render the entry node with stylesheets
  const sheet = new ServerStyleSheet()
  const markup = renderToString(sheet.collectStyles(entry))

  // Return the rendered markup with stylesheets
  return `${sheet.getStyleTags()}${markup}`
}

declare global {
  function handleRequest(request: AppRenderRequest | PartialRenderRequest): Promise<string>
}
