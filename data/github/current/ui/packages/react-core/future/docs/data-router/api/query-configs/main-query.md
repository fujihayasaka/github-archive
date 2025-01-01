# `QueryConfigs` – `mainQuery`

📄 [`ui/packages/react-core/future/query-configs.ts`](/ui/packages/react-core/future/query-configs.ts)

`mainQuery` provides a shorthand for creating a `QueryConfig` that reads `payload[routeId].mainQuery` from `embeddedData` on page load and via `json` request to the current matched route on soft-navigation. This is the most common use case for route-bound query data and should be all that is needed to provide data for most pages..

## Background

At GitHub, React routes are backed by a Rails controller/action to provide data using the `render_react_app` method of the `react_dependency`. This helper method provides data to the react app's routes throughout their lifecycle:

1. When the page is first loaded, the necessary data is injected into the rendered HTML via an `embeddedData` script tag, ensuring the data is available to the client as soon as the page is loaded.
2. On a soft navigation, the data can be fetched from rails via `json` request to the same path as the current matched route.

## Usage

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `queryOptions` | `object` | Any [`QueryConfig` options](../query-config.md) (except `queryName` and `queryFn`) can be passed to customize the query. We set [some defaults](../query-client.md#queryclient-defaults) for all queries. |

```ts
import {mainQuery} from '@github-ui/react-core/future/query-configs'
import {myExampleAppBuilder} from '../config/app-builder'

type MyResponse = {name: string}

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [mainQuery<MyResponse>()],
})
```

This creates a `QueryConfig` that reads `embeddedData` on page load and issues a `json` request to the route's path on soft navigation. The `queryName` is hard-coded to `"mainQuery"`. This is a `Blocking` query.

You can read this data in your component the same as any `QueryConfig` via `useRouteQuery`:

```tsx
import {useRouteQuery} from '@github-ui/react-core/future/data-router'
import {myExampleUserRoute} from './routes/my-example-user-route'

export function MyExampleUser() {
  const {data} = useRouteQuery(myExampleUserRoute, 'mainQuery')
  return <h1>{data.name}</h1>
}
```

## Customizing your mainQuery

You can supply `queryOptions` to override the defaults. `queryName` and `queryFn` can not be overridden.

```ts
export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    mainQuery<MyResponse>({
      staleTime: 1000 * 60 * 5, // 5 minutes
    }),
  ],
```

## Search Params

By default, `mainQuery` will send **all** search-params in the `json` request on soft navigation.

This can lead to over-fetching when search-params unrelated to your request change. For this reason it's recommended that you filter-out unused search-params as this lowers the cardinality of TanStack Query cache keys, preventing the cache from varying unnecessarily.

You can control the search-params that are included in the request via a custom `queryDeps` function.

### Filter out all search-params

If you don't want to include any search-params in your request you can use the following example:

```ts
export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    mainQuery<MyResponse>({
      // this `queryDeps` removes all search-params
      queryDeps: ({pathname}) => ({pathname}),
    }),
  ],
})
```

### Only include specific search-params

If you are only interested in sending one or two search-params, you can do something like this

```ts
export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    mainQuery<MyResponse>({
      queryDeps: ({pathname, searchParams}) => ({
        pathname,
        // only the "page" search param will be added to the `queryKey` and sent to the server.
        // We filter out any undefined or null values from the server request.
        searchParams: {
          page: searchParams.get('page'),
        },
      }),
    }),
  ],
})
```

## Customize Request

You can return an `init` from `queryDeps` to customize additional aspects of the `fetch` request suh as `headers`etc. [See `queryFnFetch` for details](../query-fn-fetch.md).

```ts
export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    mainQuery<MyResponse>({
      queryDeps: ({pathname}) => ({
        pathname,
        init: {
          headers: {
            'X-GitHub-Custom-Header': 'example',
          },
        },
      }),
    }),
  ],
})
```

## Ensure Rails controller/action provides the payload data in the correct format

DataRouter supports features like layout routes, index routes, and nested routes that mean that multiple routes can be matched and rendered for a given path. To support this, `mainQuery` expects the `payload` data provided by your Rails controller/action to be in a particular format so that it can be matched to the correct route and query.

The data must be provided to `render_react_app` via its `payload` parameter as a dictionary with the following shape:

```ruby
def show
  render_react_app(
    payload: {
      [routeId]: {
        [queryName]: query_data
      }
    }
  }
}
```

The `routeId` is name we gave to the route (eg `'myExampleUserRoute'`) and the `queryName` is the `queryName` we gave to the `QueryConfig` (`'mainQuery'` is the default `queryName` used by the `mainQuery` helper).

Note that if multiple React routes or queries are matched on the client side, a Rails controller can provide data for each of them using this format.

```ruby
def show
  render_react_app(
    payload: {
      layoutRoute: {
        mainQuery: layout_data
      },
      showRoute: {
        mainQuery: show_data
      },
    }
  }
}
```
