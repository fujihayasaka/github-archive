# `useRouteQuery`

Provides a wrapper around [`useQuery` from TanStack Query (TSQ)](https://tanstack.com/query/latest/docs/framework/react/reference/useQuery) API that provides access to the queries defined on a [`QueryRoute`](./query-route.md) without having to know its `queryKey`.

Returns a [TSQ query result](https://tanstack.com/query/v4/docs/framework/react/guides/queries) with a few additions:

1. Provides type safety for the shape of the data.
2. Returns the [generated `queryKey`](./query-config.md#querykey) for the requested `QueryConfig`.

<!-- prettier-ignore -->
   | Arguments | Type | Description |
| --- | --- | --- |
| `queryRoute` | `QueryRoute` instance | The `QueryRoute` on which the query is defined. Type information about the query, including the shape of the `data` as well as if the query is `Deferred` or `Blocking` can be inferred. |
| `queryName`  | `string` | The name of the `QueryConfig` to access. |

## Blocking vs Deferred queries

The following examples use this `QueryRoute` definition (with some details omitted for brevity)

```ts
export const showRoute = myExampleAppBuilder.createQueryRouteConfig('showRoute', {
  path: '/example/:id',
  queries: [
    {queryName: 'payload', type: QueryRouteQueryType.Blocking}
    {queryName: 'deferred', type: QueryRouteQueryType.Deferred}
  ],
})
```

### For `Blocking` queries

When the query type is `QueryRouteQueryType.Blocking`, the `data` is guaranteed to be defined when the component renders. As such you can render it unconditionally.

```tsx
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {showRoute} from './show-route'

export const Show() {
  const {data} = useRouteQuery(showRoute, 'payload')

  return (
    <>
      <h2>Show {data.id}</h2>
      <p>Hello {data.name}</p>
    </>
  )
}
```

### For `Deferred` queries

When the query is of type `QueryRouteQueryType.Deferred`, the `data` returned from `useRouteQuery` is potentially `undefined`, forcing you to define a loading state and an error state in your component.

```tsx
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {showRoute} from './show-route'

export const Show() {
  const {data, isError, isPending} = useRouteQuery(showRoute, 'deferred')
  if (isError) return <>Error!</>
  if (isPending) return <>Loading</>

  return (
    <>
      <h2>Show {data.id}</h2>
      <p>Hello {data.name}</p>
    </>
  )
}
```

## Reading the generated `queryKey` for a `QueryConfig`

As the `queryKey` for a given `QueryConfig` is generated dynamically by the framework, you can use this hook to access it along with the other related query info.

```tsx
import {useQueryClient} from '@github-ui/react-query'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {showRoute} from './showRoute'

const {data, queryKey} = useRouteQuery(showRoute, 'payload')
const queryClient = useQueryClient()

queryClient.invalidateQueries({
  queryKey,
})
```
