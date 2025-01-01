# `QueryClient`

📄 [`ui/packages/react-core/query-client.ts`](/ui/packages/react-core/query-client.ts)

All of `github/github` shares a single [TanStack Query (TSQ) `QueryClient`](https://tanstack.com/query/v5/docs/reference/QueryClient) instance. This allows us to manage query defaults, and to provide niceties like a default TSQ Devtools setup. You do not need to create a `QueryClient` instance or `QueryClientProvider` in your app.

## `useQueryClient` / `getQueryClient`

You can gain access to the shared `QueryClient` via `useQueryClient` (or `getQueryClient` outside of React).

The `QueryClient` can be used to interact with queries in the cache: for example invalidating queries after a mutation.

In general you won't need to interact with the `QueryClient` for fetching as you can use [`QueryRoute.queries`](./query-route.md)

```tsx
import {useQueryClient} from '@github-ui/rect-query'
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {showRoute} from './showRoute'

const {queryKey} = useRouteQuery(showRoute, 'payload')
const queryClient = useQueryClient()

queryClient.invalidateQueries({
  queryKey,
})
```

## `QueryClient` defaults

We override some of the [TSQ defaults](https://tanstack.com/query/v5/docs/framework/react/guides/important-defaults) to suit GitHub's needs. [You can see those overrides here](/ui/packages/react-core/query-client.ts).

## TSQ Devtools

You can access the [TSQ Devtools](https://tanstack.com/query/v5/docs/framework/react/devtools) by clicking the 🔧 wrench icon in the staffbar.
