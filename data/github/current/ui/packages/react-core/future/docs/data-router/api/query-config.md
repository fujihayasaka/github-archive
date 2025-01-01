# `QueryConfig`

[`QueryRoutes`](./query-route.md) specify their data-requirements via a `queries` key which contains an array of `QueryConfig` objects.

`QueryConfig` defines the data fetching and caching requirements of a route. It provides an API similar to TanStack Query (TSQ)'s [`QueryOptions`](https://tanstack.com/query/latest/docs/framework/react/reference/queryOptions) with a few differences. In general, any arguments supported by TSQ are supported by `QueryConfig`.

Note however that you do not set a `queryKey` directly. Instead we take care of this internally and create a query-key [based on route context](#querydeps). This helps to prevent `queryKey` collisions that can be a common source of bugs. [Read more below.](#querykey)

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `queryName`       | `string`   | A required identifier for the query. Allows access to the query and it's data via APIs like [`useRouteQuery`](./use-route-query.md) |
| `queryDeps` | `function` | Responsible for providing context to the `queryFn`. [See `queryDeps` below.](#querydeps) |
| `queryFn` | `function` | This is the function that will be called to fetch the data. [It looks like a TSQ query function](https://tanstack.com/query/latest/docs/framework/react/guides/query-functions). It must either return a `Promise` or throw an error. Receives `deps` passed from `queryDeps` to access route info in our queries. |
| `...queryOptions` | `object` | Aside from `queryKey`, the full [TSQ `QueryOptions` api is supported](https://tanstack.com/query/latest/docs/framework/react/reference/queryOptions). We set [some defaults](./query-client.md#queryclient-defaults) for all queries. |

```ts
export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    {
      queryName: 'payload',
      queryDeps: ({pathname, params, searchParams}) => {
        const page = searchParams.get('page')
        return {
          pathname,
          searchParams: {page},
        }
      },
      queryFn: async ({routeId, queryName, queryDeps}) => {
        const json = await queryFnFetch<ExampleResponse>({queryDeps})
        return json.payload[routeId][queryName]
      },
    },
  ],
})
```

## `queryName`

This is an identifier for the query. It must be unique for this route. It forms part of the `queryKey` in the query cache and is used to access the query data via the `useQueryRoute` hook (more on this later).

## `queryFn` and accessing route context via `queryDeps`

Similar to TSQ, a [`queryFn`](#queryfn) tells how to provide data for our query. Frequently that data is dependent on route context. We use the [`queryDeps`](#querydeps) function to access route context and pass it to the [`queryFn`](#queryfn) while also ensuring that our [`queryKey`](#querykey) accounts for that context.

### `queryDeps`

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `routeContext` | `object` | React Router route context. Similar to the context provided to a [React Router `loader`](https://reactrouter.com/6.28.2/route/loader) |
| `routeContext.pathname` | `string` | The actual path (as opposed to path pattern) matched for the current route. When a nested-route is matched, a parent route's `pathname` will only be the portion of the path matched by its `route.path` pattern. |
| `routeContext.params` | `object` | [Route params](https://reactrouter.com/6.28.2/route/loader#params) parsed from the dynamic segments of the current route. |
| `routeContext.searchParams` | [`URLSearchParams`](https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams) | The query string for the current route deserialized as `URLSearchParams` |
| `type` | `Blocking` \| `Deferred` | Specifies whether to suspend rendering while the query is resolved, or to render with pending data. |

`queryDeps` receives route context in the form of `{pathname, params, searchParams}` and returns `deps` which is passed to `queryFn` as well as forming part of the `queryKey`. `deps` can be an object, array or even a primitive value.

This API links the `queryKey` and `queryFn` in terms of their dependence on route context. Meanwhile it prevents over-subscribing to route context that isn't relevant to the `queryFn`.

### `queryFn`

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `queryKey` | `object` | This is an object form of the generated `queryKey` for this route. Note that the query key is ordinarily a hierarchical array, but here is's provided as an object for ease of access. |
| `queryKey.appName` | `string` | App name as defined via [`DataRouteApplicationBuilder`](./data-router-application-builder.md). |
| `queryKey.routeId` | `string` | The route identifier, as defined via [`DataRouteApplicationBuilder.createQueryRouteConfig`](./data-router-application-builder.md#createqueryrouteconfig) |
| `queryKey.path` | `string` | The route's path match. |
| `queryKey.queryName` | `string` | [The `queryName`](#queryname) defined on this `QueryConfig` |
| `queryKey.queryDeps` | `object` | The object returned from [`queryDeps`](#querydeps). |

This is the function that will be called to fetch the data. [It looks like a TSQ query function](https://tanstack.com/query/latest/docs/framework/react/guides/query-functions) but it receives the object form of the `queryKey` (including `queryDeps` returned from the `queryDeps` function) as an argument. It must either return a `Promise`, `null`, or throw an error.

## `queryKey`

You will not need to supply a `queryKey` for your query. Instead we will create one for you from route info and `queryDeps`. [See `makeQueryKey` for details](/ui/packages/react-core/query-key.ts).

If you need the query key, you can read it via [`useRouteQuery`](./use-route-query.md#reading-the-generated-querykey-for-a-queryconfig).

## `type`

This specifies whether the query is `Blocking` or `Deferred`.

- `QueryRouteQueryType.Blocking`: If the query is not in the cache, rendering will be suspended until the query is resolved. Data will always be available when the component is rendered. We should prefer to use blocking queries wherever possible to provide the most complete and consistent user experience.
- `QueryRouteQueryType.Deferred`: We start rendering before the query is resolved. If the query is not in the cache, rendering will not be suspended; instead, the component will render with data in the `isPending` state. This allows us to provide a custom loading state and optimize the HPC of the initial render. The query will be resolved in the background and the component will re-render when the query is resolved. [Read about query `status` and `fetchStatus` for more information](https://tanstack.com/query/latest/docs/framework/react/guides/queries).

If you don't specify a `type`, the query will be `Blocking` by default.

**NB:** Most routes should only require a single `Blocking` query and possibly a single additional `Deferred` query to offload secondary content to.
