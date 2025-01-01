import {controller} from '@github/catalyst'
import {createBrowserRouter, RouterProvider} from 'react-router-dom'
import {createBrowserHistory} from './create-browser-history'
import type {EmbeddedData} from './embedded-data-types'
import {applyRouterNavigateOverride} from './future/apply-router-navigate-override'
import {getReactDataRouterApp, type DataRouterAppRegistrationFn} from './future/data-router-app-registry'
import {routesWithProviders} from './future/RoutesWithProviders'
import {getReactNavigatorApp, type NavigatorAppRegistrationFn} from './navigator-app-registry'
import {NavigatorClientEntry} from './NavigatorClientEntry'
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

// What is this silliness? Is it react or a web component?!
// It's a web component we use to bootstrap react apps within the monolith.
@controller
export class ReactAppElement extends ReactBaseElement<EmbeddedData> {
  nameAttribute = 'app-name'

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

    const router = createBrowserRouter(
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

    applyRouterNavigateOverride(router)

    return <RouterProvider router={router} future={v7_routeProviderFutureFlags} />
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

    const history = createBrowserHistory({window})
    const {key, state} = history.location
    const initialLocation = {
      pathname,
      search,
      hash,
      key,
      state,
    }

    return (
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
    )
  }

  get isLazy() {
    return this.getAttribute('data-lazy') === 'true'
  }
}
