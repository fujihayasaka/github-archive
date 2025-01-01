import {controller} from '@github/catalyst'
import {generateAppId, registerAppId} from '@github-ui/app-uuid'
import {currentState, updateCurrentState} from '@github-ui/history'
import type {Router} from '@remix-run/router'
import {createBrowserRouter, RouterProvider} from 'react-router-dom'

import {createBrowserHistory, type GitHubBrowserHistory} from './create-browser-history'
import type {EmbeddedData} from './embedded-data-types'
import {applyRouterNavigateOverride} from './future/apply-router-navigate-override'
import {type DataRouterAppRegistrationFn, getReactDataRouterApp} from './future/data-router-app-registry'
import {routesWithProviders} from './future/RoutesWithProviders'
import {getReactNavigatorApp, type NavigatorAppRegistrationFn} from './navigator-app-registry'
import {NavigatorClientEntry} from './NavigatorClientEntry'
import {Profiler, ProfilerProvider} from './ProfilerContext'
import {getQueryClient} from './query-client'
import {v7_routeProviderFutureFlags, v7_routerFutureFlags} from './react-router-future-flags'
import {ReactBaseElement} from './ReactBaseElement'

declare global {
  namespace JSX {
    interface IntrinsicElements {
      'react-app': React.DetailedHTMLProps<React.HTMLAttributes<ReactAppElement>, ReactAppElement>
    }
  }
}

// Copied from React Router
const createKey = () => Math.random().toString(36).substr(2, 8)

// What is this silliness? Is it react or a web component?!
// It's a web component we use to bootstrap react apps within the monolith.
@controller
export class ReactAppElement extends ReactBaseElement<EmbeddedData> {
  nameAttribute = 'app-name'
  declare uuid: string
  declare routerOrHistory: Router | GitHubBrowserHistory

  override connectedCallback() {
    super.connectedCallback()
    this.uuid = generateAppId()
    registerAppId(this.uuid)

    window.addEventListener('popstate', this.popStateListener, true)
  }

  popStateListener = (e: PopStateEvent) => {
    // not having a new state means it's a hash navigation
    if (e.state && this.uuid !== currentState().appId) this.routerOrHistory?.dispose()
  }

  override disconnectedCallback() {
    window.removeEventListener('popstate', this.popStateListener, true)
    this.routerOrHistory?.dispose()
    super.disconnectedCallback()
  }
  // The component that wraps this React app will know if the app should be rendered with
  // date router (instead of navigator router) and it does this by setting
  // a `data-data-router-enabled="true"` attribute on this `<react-app>` element.
  // Remember we might have two apps called `some-cool-app`, because it started as a navigator app
  // (i.e. jsonRoute) and now also exists a data router app (i.e. queryRoute). At runtime, we might
  // toggle between which to use based on feature flags.
  get isDataRouterEnabled() {
    return this.getAttribute('data-data-router-enabled') === 'true'
  }

  async getReactNode(embeddedData: EmbeddedData, onError: (error: Error) => void): Promise<JSX.Element> {
    if (this.isDataRouterEnabled) {
      const app = await getReactDataRouterApp(this.name)
      return this.#getDataRouterNode(embeddedData, onError, app.registration)
    }

    const app = await getReactNavigatorApp(this.name)
    return this.#getNavigatorNode(embeddedData, onError, app.registration)
  }

  async #getDataRouterNode(
    embeddedData: EmbeddedData,
    onError: (error: Error) => void,
    registration: DataRouterAppRegistrationFn,
  ) {
    if (embeddedData) {
      const queryClient = getQueryClient()
      queryClient.removeQueries({queryKey: [this.name]})
    }
    const {routes} = registration({
      // when we hydrated the queryClient directly, we don't want to add initialData again
      embeddedData,
    })

    this.routerOrHistory = createBrowserRouter(
      routesWithProviders(routes, {
        appPayload: embeddedData.appPayload,
        ssrError: this.ssrError,
        appName: this.name,
        wasServerRendered: this.hasSSRContent,
        dataRouterEnabled: true,
      }),
      {
        future: v7_routerFutureFlags,
      },
    )

    applyRouterNavigateOverride(this.routerOrHistory)

    return (
      <ProfilerProvider appName={this.name} isDataRouterEnabled>
        <Profiler id={this.name}>
          <RouterProvider router={this.routerOrHistory} future={v7_routeProviderFutureFlags} />
        </Profiler>
      </ProfilerProvider>
    )
  }

  async #getNavigatorNode(
    embeddedData: EmbeddedData,
    onError: (error: Error) => void,
    registration: NavigatorAppRegistrationFn,
  ) {
    const {App, routes} = registration()
    const initialPath = this.getAttribute('initial-path') as string

    if (this.isLazy) {
      const request = await fetch(initialPath, {
        mode: 'no-cors',
        cache: 'no-cache',
        credentials: 'include',
      })
      const {payload} = await request.json()

      embeddedData.payload = payload
    }

    const window = globalThis.window as Window | undefined

    // Initial path is set by ruby. Anchors are not sent to the server.
    // Therefore anchors must be set explicitly by the client.
    const {pathname, search, hash} = new URL(
      `${initialPath}${window?.location.hash ?? ''}`,
      window?.location.href ?? 'https://github.com',
    )

    // set the `key` property to avoid using `default` as the initial location's `key`.
    updateCurrentState({key: createKey()})

    const history = createBrowserHistory({window})
    this.routerOrHistory = history
    const {key, state} = history.location
    const initialLocation = {
      pathname,
      search,
      hash,
      key,
      state,
    }

    return (
      <ProfilerProvider appName={this.name} isDataRouterEnabled={false}>
        <Profiler id={this.name}>
          <NavigatorClientEntry
            appName={this.name}
            initialLocation={initialLocation}
            history={history}
            embeddedData={embeddedData}
            routes={routes}
            App={App}
            wasServerRendered={this.hasSSRContent}
            ssrError={this.ssrError}
            onError={onError}
          />
        </Profiler>
      </ProfilerProvider>
    )
  }

  get isLazy() {
    return this.getAttribute('data-lazy') === 'true'
  }
}
