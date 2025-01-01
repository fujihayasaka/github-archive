# Introduction to React `DataRouter` and `QueryRoute`

`DataRouter` / `QueryRoute` is the data-fetching and caching API we use at GitHub to synchronize data between Rails and React apps.

`DataRouter` provides the following features:

1. Route-based data-fetching:
   1. The core of `DataRouter` is built with [React Router v6](https://reactrouter.com) and its [`loaders` API](https://reactrouter.com/6.28.1/route/loader).
   2. React data fetching is tied, by convention, to a controller/action at the same route as the React route.
   3. Preloaded data: On first page load, the React app is hydrated with initial data via JSON embedded in a script tag, saving an additional round trip to the server.
   4. SSR Data: Data is provided to Alloy for SSR rendering.
   5. Blocking data: route transitions are blocked via Suspense until critical, blocking fetched data is resolved, providing a simple, synchronous data-fetching API.
   6. Deferred data: auxiliary data can be defined on a route that doesn't block initial render allowing for optimized HPC. Instead, developers must provide a loading state for deferred data.
   7. Both blocking and deferred data is fetched immediately on route transitions and is resolved in parallel with React rendering.
   8. Custom queries can be defined to request data from arbitrary sources.
2. Data-request caching
   1. `DataRouter` uses [TanStack Query (TSQ)](https://tanstack.com/query/latest) to cache data requests. Subsequent requests for the same data are instantly returned from cache while revalidating the data from the server.
   2. Data needs are expressed as [`QueryConfig` objects](./api/query-config.md) defined on a [`QueryRoute`](./api/query-route.md). This provides a familiar TSQ API for defining the data-requirements for a route.
   3. A familiar TSQ `queryKey` API is exposed to allow developers to invalidate data caches via `queryClient.invalidateQueries` and friends.

## Example app

Check out the React Sandbox Future app for a working example of building with `DataRouter` and `QueryRoute`.

- [⚛️ React code: `ui/packages/react-sandbox-future/`](/ui/packages/react-sandbox-future/README.md)
- [🚃 Rails code: `app/controllers/react_sandbox_future_controller.rb`](/app/controllers/react_sandbox_future_controller.rb)

You can also see the PR Commits app for a real-life example: [`ui/packages/pull-requests/pull-requests.ts`](/ui/packages/pull-requests/pull-requests.ts).

## What's next

- [🚀 Quick Start](./02-quick-start.md)
- [🧾 API reference](./api/)
- [👨🏻‍🍳 Recipes](./recipes/)
- [🗣️ Slack](https://gh.io/data-router-feedback-slack)
- [📝 Feedback discussion](https://gh.io/data-router-feedback)
