# `QueryRoute`

📄 [`ui/packages/react-core/future/data-router-application.ts`](../../../data-router-application.ts#L217)

`QueryRoute` provides an API for defining a route along with its data-requirements.
The route information follows the [React Router Route API](https://reactrouter.com/6.28.1/route/route), although JSX rendering attributes such as `Component`, `children` etc. are specified in a separate `queryRoute.toRoute()` step.

`QueryRoute` leverages [TanStack Query (TSQ)](https://tanstack.com/query/) for data fetching and caching.

Note that `QueryRoute` is not a React Router compatible route definition. You must call [`queryRoute.toRoute`](#toroute) and supply rendering args to create a React Router compatible route.

## `DataRouterApplicationBuilder.createQueryRouteConfig`

You don't create `QueryRoute` instances directly, instead, `QueryRoute` instances are created by invoking [`createQueryRouteConfig`](./data-router-application-builder.md#createqueryrouteconfig) on your application's `DataRouterApplicationBuilder` instance.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `routeId` | `string` | A unique identifier for the route. becomes `queryRoute.id`. This `id` is used in rails to match data to a route allowing for a controller to provide data for embedded routes |
| `queryRouteArgs` | `object` | An object of [route args](https://reactrouter.com/6.28.2/route/route) and queries. Note that component and rendering props (`element`/`Component`, `children`, `errorElement`/`ErrorBoundary`, `hydrateFallbackElement`/`HydrateFallback`) are not specified at this time. Instead, they are specified while composoing the app via [`DataRouterApplicationBuilder.createDataRouterAppFromRoutes`](./data-router-application-builder.md#createdatarouterappfromroutes) |
| `queryRouteArgs.path` | `string` | This is a React Router path pattern. If a path segment starts with `:` then it becomes a ["dynamic segment"](https://reactrouter.com/start/framework/routing#dynamic-segments).` When the route matches the URL, the dynamic segment will be parsed from the URL and provided as params to other router APIs |
| `queryRouteArgs.index` | `boolean` | Determines if the route is [an index route](https://reactrouter.com/6.28.2/route/route#index). Index routes render into their parent's [Outlet](https://reactrouter.com/6.28.2/components/outlet) at their parent's URL (like a default child route). [See also this guide](https://reactrouter.com/6.28.2/start/concepts#index-routes). |
| `queryRouteArgs.queries` | [`QueryConfig[]`](./query-config.md) | Defines the data requirements for a route using a familiar TanStack Query API. See [`QueryConfig` for details](./query-config.md) |

```ts
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import {myExampleAppBuilder} from '../config/app-builder'

export const myExampleShowRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleShowRoute', {
  path: '/example/:id',
  queries: [
    {
      queryName: 'payload',
      queryDeps: ({pathname, searchParams}) => ({
        pathname,
        searchParams: {
          page: searchParams.get('page'),
        },
      }),
      queryFn: async queryKey => queryFnFetch<ExampleResponse>(queryKey),
    },
  ],
})
```

## `toRoute`

Called during app creation via [`DataRouterApplicationBuilder.createDataRouterAppFromRoutes`](./data-router-application-builder.md#createdatarouterappfromroutes) to create a route by merging the `QueryRoute` with the passed component props.

Note: the separation of "component props" and "route props" is important to avoid potential circular dependencies between the components and the `QueryRoute`.
Any [`QueryConfigs`](./query-config.md) defined on `QueryRoute.queries` are transformed into TSQ `QueryOptions` and fetched via TSQ in a generated ReactRouter `loader`.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `components` | `object` | The React Router [Route component props](https://reactrouter.com/6.28.2/route/route) that were excluded from the `QueryRoute`: ([`element`/`Component`](https://reactrouter.com/6.28.2/route/route#elementcomponent), [`children`](https://reactrouter.com/6.28.2/route/route#children), [`errorElement`/`ErrorBoundary`](https://reactrouter.com/6.28.2/route/route#errorelementerrorboundary), [`hydrateFallbackElement`/`HydrateFallback`](https://reactrouter.com/6.28.2/route/route#hydratefallbackelementhydratefallback)) |

```ts
import {myExampleAppBuilder} from './config/app-builder'
import {layoutRoute} from './routes/layout-route'
import {Layout} from './routes/Layout'
import {homeRoute} from './routes/home-route'
import {Home} from './routes/Home'
import {showRoute} from './routes/show-route'
import {Show} from './routes/Show'

export const myExampleApp = myExampleAppBuilder.createDataRouterAppFromRoutes([
  layoutRoute.toRoute({
    Component: Layout,
    children: [homeRoute.toRoute({Component: Home}), showRoute.toRoute({Component: Show})],
  }),
])
```

## `generatePath`

A helper that can be used to generate links to this route. Provides type-safety about required `params`.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `params` | `PathParams` | An object of required path params from which to generate the path |
| `routeInfo` | `object` | Additional route info |
| `routeInfo.search` | [`URLSearchParams`](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams) | Any query-string to add to the path |
| `routeInfo.hash`   | `string` | A hash to add to the path |

```tsx
<Link to={myExampleRoute.generatePath({id: 123}, {page: 2})}>Item 123 (Page 2)</Link>
```

## `isSameRoute`

Check if a passed route matches the current route instance. This is used by the framework in certain cases.
