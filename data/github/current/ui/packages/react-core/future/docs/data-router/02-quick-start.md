# Quick Start

This guide is intended to get you up and running with `DataRouter` and `QueryRoute`. It provides a step by step walk-through of setting up a React app in the `github/github` repo including routing and data. For an overview of the framework, [see the introduction](./01-introduction.md).

- [Quick Start](#quick-start)
  - [0. Generators (TODO)](#0-generators-todo)
  - [1. Scaffold a new React app](#1-scaffold-a-new-react-app)
  - [2. Update your app](#2-update-your-app)
  - [3. Define an App-Builder](#3-define-an-app-builder)
  - [4. Define your routes](#4-define-your-routes)
    - [The first route is the **home route**.](#the-first-route-is-the-home-route)
    - [Next lets define a route with a dynamic segment.](#next-lets-define-a-route-with-a-dynamic-segment)
  - [5. Register your routes](#5-register-your-routes)
  - [6. Link to your routes](#6-link-to-your-routes)
  - [7. Add a layout](#7-add-a-layout)
    - [Register the layout](#register-the-layout)
  - [8. Index route](#8-index-route)
  - [9. Fetching route data with `queryRoute`](#9-fetching-route-data-with-queryroute)
    - [`queryKey`](#querykey)
    - [`queryName`](#queryname)
    - [`queryFn`](#queryfn)
    - [`type`](#type)
  - [10. Use `queryDeps` to access route info in your query function](#10-use-querydeps-to-access-route-info-in-your-query-function)
  - [11. Use `queryFnFetch` to simplify fetch handling boilerplate](#11-use-queryfnfetch-to-simplify-fetch-handling-boilerplate)
  - [12. Use `mainQuery` to streamline access to route-bound data](#12-use-mainquery-to-streamline-access-to-route-bound-data)
    - [Upgrade your query to `mainQuery`](#upgrade-your-query-to-mainquery)
    - [Update your Rails controller/action to provide the data in the correct format](#update-your-rails-controlleraction-to-provide-the-data-in-the-correct-format)
  - [13. Accessing query data in your component with `useRouteQuery`](#13-accessing-query-data-in-your-component-with-useroutequery)
  - [14. Add a deferred query to optimize HPC](#14-add-a-deferred-query-to-optimize-hpc)
  - [Congratulations!](#congratulations)
    - [Next steps](#next-steps)

## 0. Generators (TODO)

> TODO: We will add generators via `scaffold-ui-package` to automate this setup (see [`react-platform#191`](https://github.com/github/react-platform/issues/191)). For now you can start from a Navigator / `jsonRoute` app and follow the steps below.

## 1. Scaffold a new React app

```sh
scaffold-ui-package
```

Choose `"React App - Create a React App"`, follow the prompts and commit your work.

For this example we'll use `my-example` as the package name. You can replace this with the name of your package.

## 2. Update your app

First we need to replace `registerNavigatorApp` with a `registerDataRouterApp` in your app's entry file.

**📄 `ui/packages/my-example/my-example.ts`**

```diff
-import {registerNavigatorApp} from '@github/react-core/register-app'
+import {registerDataRouterApp} from '@github/react-core/register-app'
+import {myExampleAppBuilder} from './config/app-builder'

-registerDataRouterApp('myExample', () => {
- // .... snip routes ....
-})
+export const myExampleApp = myExampleAppBuilder.createDataRouterAppFromRoutes([
+ // TODO: add routes
+])
+registerDataRouterApp(myExampleApp)
```

This swaps the underlying routing engine from the [navigator-router](../../../NavigatorRouter.tsx) to the [`DataRouter`](../../../ReactAppElement.tsx#38). The `DataRouter` is built on top of [React Router](https://reactrouter.com) and uses its [`loaders`](https://reactrouter.com/6.28.2/route/loader) API to define data-fetching requirements for a route.

The [`myExampleAppBuilder.createDataRouterAppFromRoutes`](./api/data-router-application-builder.md#createdatarouterappfromroutes) takes a `routes` array argument. It's empty for now; we'll come back to this in a moment.

> [!IMPORTANT]
> Note that we can no longer declare our routes inline. To avoid circular dependencies, we must define them in separate files.

We export the created `myExampleApp` instance so that we can use it in tests.

Just like `registerNavigatorApp`, this registers our app in the deferred registry ready to be rendered by the [`react-app` web-component](../../../ReactAppElement.tsx).

## 3. Define an App-Builder

You may have noticed that we import `myExampleAppBuilder` from `config/app-builder.ts` which doesn't exist yet. Let's create the [`DataRouterApplicationBuilder`](./api/data-router-application-builder.md) instance now.

Create a new file `ui/packages/my-example/config/app-builder.ts` and define your app-builder.

**📄 `ui/packages/my-example/config/app-builder.ts`**

```ts
import {DataRouterApplicationBuilder} from '@github-ui/react-core/future/$$data-router-application'

export const myExampleAppBuilder = DataRouterApplicationBuilder.create('my-example')
```

We use the app-builder to create our and configure our app. We used it above to create and register the app for rendering. We'll use it again later to add routes to the app.

The `name` argument must match the name of your package.

## 4. Define your routes

Next we need to define our routes. We'll start with just two routes for now. Each route is comprised of two files: a route config and a component.

### The first route is the **home route**.

This is just a simple route that matches on `/`. Let's create it using [`myExampleAppBuilder.createQueryRouteConfig`](./api/data-router-application-builder.md#createqueryrouteconfig)

**📄 `ui/packages/my-example/routes/home-route.ts`**

```ts
import {myExampleAppBuilder} from '../config/app-builder'

export const myExampleHomeRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleHomeRoute', {
  path: '/example',
})
```

This creates a [`QueryRoute`](./api/query-route.md) instance. a `QueryRoute` is not yet a complete React Router-compatible route: to avoid a circular dependency, we don't specify a `component` here. We'll see in a moment how to convert a `QueryRoute` into a React Router route.

The component lives along-side the route in a separate file and might look like this:

**📄 `ui/packages/my-example/routes/Home.tsx`**

```tsx
export function MyExampleHome() {
  return <h2>Home</h2>
}
```

### Next lets define a route with a dynamic segment.

**📄 `ui/packages/my-example/routes/user-route.ts`**

```ts
import {myExampleAppBuilder} from '../config/app-builder'

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
})
```

The component might look like this:

**📄 `ui/packages/my-example/routes/User.tsx`**

```tsx
import {useRouteParams} from '@github-ui/react-core/future/use-route-params'
import {myExampleUserRoute} from ./user-route

export const MyExampleUser: React.FC = () => {
  const {id} = useRouteParams(myExampleUserRoute)
  return <h2>User {id}</h2>
}
```

We're accessing the value of the dynamic segment via [`useRouteParams`](./api/use-route-params.md). The `myExampleUserRoute` `QueryRoute` passed to `useRouteConfig` allows us to provide type-safe access to the route's parameters.

## 5. Register your routes

We can now go back to the app entry (`my-example.ts`) and register our routes.

We convert our `QueryRoute` instances into React Router routes by calling their [`toRoute`](./api/query-route.md#toroute) method. The `toRoute` method combines the route-config, defined on the `QueryRoute` instance, with a render config, passed as arguments. In the example below we're defining `Component` props for our routes via render configs.

**📄 `ui/packages/my-example/my-example.ts`**

```diff
import {registerDataRouterApp} from '@github/react-core/future'
import {myExampleAppBuilder} from './config/app-builder'
+import {myExampleHomeRoute} from './routes/home-route'
+import {MyExampleHome} from './routes/Home'
+import {myExampleUserRoute} from './routes/user-route'
+import {MyExampleUser} from './routes/User'

export const myExampleApp = myExampleAppBuilder.createDataRouterAppFromRoutes([
-  // TODO: add routes
+  myExampleHomeRoute.toRoute({Component: MyExampleHome}),
+  myExampleUserRoute.toRoute({Component: MyExampleUser}),
+])
+
registerDataRouterApp(myExampleApp)
```

Now when you visit `/` you should see **"Home"** and when you visit `/users/123` you should see **"User 123"** in your browser.

## 6. Link to your routes

You can use the `Link` component from `react-router` to link to your routes.

The `QueryRoute` instance provides a [`generatePath`](./api/query-route.md#generatepath) method that provides a type-safe way to generate URLs for your routes that will update as your routes change.

**📄 `ui/packages/my-example/routes/Home.tsx`**

```tsx
import {Link} from 'react-router-dom'
import {myExampleUserRoute} from './home-route'

export const MyExampleHome: React.FC = () => {
  return (
    <div>
      <h2>Home</h2>
      <h3>Users</h3>
      <ul>
        <li>
          <Link to={myExampleUserRoute.generatePath({id: 1})}>View User 1</Link>
        </li>
        <li>
          <Link to={myExampleUserRoute.generatePath({id: 2})}>View User 2</Link>
        </li>
      </ul>
    </div>
  )
}
```

## 7. Add a layout

You may want to add a [layout to your app](https://reactrouter.com/start/library/routing#layout-routes). This is a component that wraps all of your app's routes. You can use a layout to provide common UI or wrap your app with common providers.

Again, we'll need to add a route-config and a component for our layout.

**📄 `ui/packages/my-example/routes/layout-route.ts`**

```ts
import {myExampleAppBuilder} from '../config/app-builder'

export const myExampleLayoutRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleLayoutRoute', {
  path: '/example',
})
```

**📄 `ui/packages/my-example/routes/Layout.tsx`**

```tsx
import {myExampleHomeRoute} from './home-route'

export const MyExampleLayout: React.FC = () => {
  return (
    <div>
      <h1>My App</h1>
      <nav>
        <ul>
          <li>
            <Link to={myExampleHomeRoute.generatePath()}>Home</Link>
          </li>
        </ul>
      </nav>
      <div>
        <Outlet />
      </div>
    </div>
  )
}
```

Note the [`<Outlet />` component](https://reactrouter.com/6.28.2/components/outlet). [This is where the nested routes will be rendered](https://reactrouter.com/tutorials/address-book#nested-routes-and-outlets).

### Register the layout

We now need to update our route structure to include the layout. To do this we will use nested routes to render the `myExampleHomeRoute` and `myExampleUserRoute` inside the `myExampleLayoutRoute`.

**📄 `ui/packages/my-example/my-example.ts`**

```diff
import {registerDataRouterApp} from '@github/react-core/future'
import {myExampleAppBuilder} from './config/app-builder'
+import {myExampleLayoutRoute} from './routes/layout-route'
+import {MyExampleLayout} from './routes/Layout'
import {myExampleHomeRoute} from './routes/home-route'
import {MyExampleHome} from './routes/Home'
import {myExampleUserRoute} from './routes/user-route'
import {MyExampleUser} from './routes/User'

export const myExampleApp = myExampleAppBuilder.createDataRouterAppFromRoutes([
-  myExampleHomeRoute.toRoute({Component: MyExampleHome}),
-  myExampleUserRoute.toRoute({Component: MyExampleUser}),
+  myExampleLayoutRoute.toRoute({Component: MyExampleLayout, children: [
+    myExampleHomeRoute.toRoute({Component: MyExampleHome}),
+    myExampleUserRoute.toRoute({Component: MyExampleUser}),
+  ]}),
])
```

## 8. Index route

Note that `myExampleLayoutRoute` and `myExampleHomeRoute` have the same path. This means that `/example` will render both components. To avoid this, we can make `myExampleHomeRoute` [an index route.](https://reactrouter.com/start/library/routing#index-routes)

**📄 `ui/packages/my-example/routes/home-route.ts`**

```diff
import {myExampleAppBuilder} from '../config/app-builder'

export const myExampleHomeRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleHomeRoute', {
  path: '/example',
+ index: true,
})
```

Now `myExampleHomeRoute` will render in it's parent's [`<Outlet />`](https://reactrouter.com/6.28.2/components/outlet) when the path matches the parent's path exactly (eg. `/`).

## 9. Fetching route data with `queryRoute`

Let's fetch some data for our `MyExampleUser` component. `DataRouter` uses a route-based data-fetching approach based on [React Router's loaders](https://reactrouter.com/guides/data-fetching#loaders) and [TanStack Query](https://tanstack.com/query/latest). This allows us to declaratively define the data requirements for a route and have the data automatically fetched on route transitions before we even start rendering the component.

We define the data requirements for a route by adding one or more [`QueryConfig` objects](./api/query-config.md) to the route's `queries` array. These are similar to [TSQ `QueryConfig` objects](https://tanstack.com/query/latest/docs/framework/react/reference/queryOptions) and support many of the same features as TSQ.

**📄 `ui/packages/my-example/routes/user-route.ts`**

```diff
+import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
+import {reactFetchJSON} from '@github-ui/verified-fetch'
import {myExampleAppBuilder} from '../config/app-builder'

+type MyResponse = {name: string}

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
   path: '/example/users/:id',
+  queries: [
+    {
+      queryName: 'payload',
+      queryFn: async () => {
+        const id = 123 // TODO we'll fix this a little later
+        const response = await reactFetchJSON(`/example/users/${id}`)
+        if (!response.ok) {
+           throw new Error(`${response.status} on ${response.url}`)
+        }
+        return response.json() as MyResponse
+      },
+      type: QueryRouteQueryType.Blocking,
+    },
+  ],
})
```

There's a lot going on here so lets break it down.

### [`queryKey`](./api/query-config.md#querykey)

First of all, if you are familiar with [TanStack Query](https://tanstack.com/query/latest) you may be wondering why we are not defining a `queryKey` for the query. The `queryKey` is automatically generated based on the `queryName` and route info. This means that the `queryKey` is unique to the route and the query. `queryKey` collisions are a common source of bugs when using TSQ and by generating the `queryKey` for you, we can avoid this problem.

### [`queryName`](./api/query-config.md#queryname)

This is an identifier for the query. It must be unique for this route. It forms part of the `queryKey` in the query cache and is used to access the query data via the `useQueryRoute` hook (more on this later).

### [`queryFn`](./api/query-config.md#queryfn)

This is the function that will be called to fetch the data. [It looks like a TSQ query function](https://tanstack.com/query/latest/docs/framework/react/guides/query-functions). It must either return a `Promise` or throw an error. We'll see later how we can use `queryDeps` to access route info in our queries.

### [`type`](./api/query-config.md#type)

This specifies whether the query is `Blocking` or `Deferred`.

- `QueryRouteQueryType.Blocking`: If the query is not in the cache, rendering will be suspended until the query is resolved. Data will always be available when the component is rendered. We should prefer to use blocking queries wherever possible to provide the most complete and consistent user experience.
- `QueryRouteQueryType.Deferred`: We start rendering before the query is resolved. If the query is not in the cache, rendering will not be suspended; instead, the component will render with data in the `isPending` state. This allows us to provide a custom loading state and optimize the HPC of the initial render. The query will be resolved in the background and the component will re-render when the query is resolved. [Read about query `status` and `fetchStatus` for more information](https://tanstack.com/query/latest/docs/framework/react/guides/queries).

If you don't specify a `type`, the query will be `Blocking` by default.

**NB:** Most routes should only require a single `Blocking` query and possibly a single additional `Deferred` query to offload secondary content to.

## 10. Use `queryDeps` to access route info in your query function

Most queries will need to use the route info to fetch the correct data. [The `queryDeps` function](./api/query-config.md#querydeps) allows you to access the route info for the current route. The return value of `queryDeps` will be added to the [`queryKey`](<(./api/query-config.md#querykey)>) and passed as arguments to the [`queryFn`](./api/query-config.md#queryfn).

**📄 `ui/packages/my-example/routes/user-route.ts`**

```diff
import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
import {reactFetchJSON} from '@github-ui/verified-fetch'
import {myExampleAppBuilder} from '../config/app-builder'

type MyResponse = {name: string}

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    {
      queryName: 'payload',
+     queryDeps: ({params}) => {
+       return {id: params.id}
+     },
+     queryFn: async ({queryDeps: {id}}) => {
-     queryFn: async () => {
-       const id = 123
        const response = await reactFetchJSON(`/example/users/${id}`)
        if (!response.ok) {
           throw new Error(`${response.status} on ${response.url}`)
        }
        return response.json() as MyResponse
      },
      type: QueryRouteQueryType.Blocking,
    },
  ],
})
```

By separating reading route info from the `queryFn`, `queryDeps` ensures that the `queryKey` is aware of route-dependent data allowing the query to automatically re-fetch only when the pertinent route info changes.

## 11. Use `queryFnFetch` to simplify fetch handling boilerplate

There's still some boilerplate involved in preparing the request and handling the response. We can simplify this by using the [`queryFnFetch`](./api/query-fn-fetch.md) helper.

`queryFnFetch` works hand-in-hand with `queryDeps`, and handles tracing, error handling, and parsing the json response.

```diff
import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
+import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
-import {reactFetchJSON} from '@github-ui/verified-fetch'
import {myExampleAppBuilder} from '../config/app-builder'

type MyResponse = {name: string}

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    {
      queryName: 'payload',
+     queryDeps: ({pathname}) => ({pathname}),
      // queryFnFetch pulls `pathname`, `searchParams`, and `init` from `queryKey.queryDeps` to make the request
+     queryFn: async queryKey => queryFnFetch<MyResponse>(queryKey),
-     queryDeps: ({params}) => {
-       return {id: params.id}
-     },
-     queryFn: async ({queryDeps: {id}}) => {
-       const response = await reactFetchJSON(`/example/users/${id}`)
-       if (!response.ok) {
-         throw new Error(`${response.status} on ${response.url}`)
-       }
-       return response.json() as MyResponse
-     },
      type: QueryRouteQueryType.Blocking,
    },
  ],
})
```

## 12. Use `mainQuery` to streamline access to route-bound data

At GitHub, React routes are backed by a Rails controller/action to provide data using the `render_react_app` method of the `react_dependency`. This helper method provides data to the react app's routes throughout their lifecycle:

1. When the page is first loaded, the necessary data is injected into the rendered HTML via a `embeddedData` script tag, ensuring the data is available to the client as soon as the page is loaded.
2. On a soft navigation, the data can be fetched from rails via `json` request to the same path as the current matched route.

### Upgrade your query to `mainQuery`

DataRouter provides an `mainQuery` function that creates a `QueryConfig` that handles reading the `embeddedData` on page load and issuing the `json` request on soft navigation (This is a drop in replacement for `jsonRoute` in Navigator apps).

We can replace the hand-rolled `QueryConfig` we defined above with an `mainQuery` to streamline access to the route-bound data.

**📄 `ui/packages/my-example/routes/user-route.ts`**

```diff
+import {mainQuery} from '@github-ui/react-core/future/query-configs'
-import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
-import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import {myExampleAppBuilder} from '../config/app-builder'

type MyResponse = {name: string}

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
+    mainQuery<MyResponse>()
-    {
-      queryName: 'payload',
-      queryDeps: ({pathname}) => ({pathname}),
-      queryFn: async queryKey => queryFnFetch<MyResponse>(queryKey),
-      type: QueryRouteQueryType.Blocking,
-    },
  ],
})
```

That's all it takes to wire-up your route to receive data from the Rails Backend!

### Update your Rails controller/action to provide the data in the correct format

`mainQuery` expects the data to be in a particular format so that it can be matched to the correct route and query when there are multiple nested routes rendered on a page.

The data is provided to `render_react_app` via its `payload` parameter and is a dictionary with the following shape

```ruby
{
  [routeId]: {
    [queryName]: queryData
  }
}
```

The `routeId` is name we gave to the route (eg 'myExampleUserRoute') and the `queryName` is the `queryName` we gave to the `QueryConfig` (`'mainQuery'` is the default `queryName` used by the `mainQuery` helper). Note that if multiple React routes or queries are matched on the client side, a Rails controller can provide data for each of them using this format.

Let's update our Rails controller to provide the data in the correct format.

**📄 `app/controllers/example/users_controller.rb`**

```diff
  def show
    render_react_app(
      payload: {
-       user: {name: "User #{params[:id]}"},
+       myExampleUserRoute: {
+         mainQuery: {name: "User #{params[:id]}"},
+         title: "Example User",
+       },
      },
-     title: "Example User",
+     data_router_enabled: true,
    )
  end
```

Notice that we've also added `data_router_enabled: true` to the `render_react_app` call. This tells the `react_dependency` to render the app using `DataRouter` instead of `NavigatorRouter`. This is necessary while we transition off of Navigator. If you are upgrading an existing Navigator app, you can pass a feature flag to `data_router_enabled` to switch between router implementations.

Also, note that the `title` is now part of the `myExampleUserRoute` and not a "general" keywoard argument to
`render_react_app`. This allows us to pick the correct title on the client when multiple routes are rendered
for the same URL.

## 13. Accessing query data in your component with `useRouteQuery`

We can use the [`useRouteQuery` hook](./api/use-route-query.md) to access the query data in our component.

**📄 `ui/packages/my-example/routes/User.tsx`**

```diff
+import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {useRouteParams} from '@github-ui/react-core/future/use-route-params'
import {myExampleUserRoute} from ./user-route

export const MyExampleUser: React.FC = () => {
+ const {data} = useRouteQuery(myExampleUserRoute, 'mainQuery')
  const {id} = useRouteParams(myExampleUserRoute)
- return <h2>User {id}</h2>
+ return (
+   <>
+     <h2>User {id}</h2>
+     <p>Hello {data.name}</p>
+   </>
+ )
}
```

`useRouteQuery` is a wrapper around [TSQ's `useQuery` hook](https://tanstack.com/query/latest/docs/framework/react/reference/useQuery) that provides a type-safe way to access the query data. The first argument is a [`QueryRoute` instance](./api/query-route.md) and the second argument is the[ `queryName` of a `QueryConfig`](./api/query-config.md#queryname). The `QueryConfig` instance allows us to provide type-safety to the query `data` as well as ensure we are accessing the correct query.

In addition to the `data`, we can access [the full TSQ `useQuery` result object](https://tanstack.com/query/v4/docs/framework/react/guides/queries). Additionally, we can access the generated [`queryKey`](./api/use-route-query.md#reading-the-generated-querykey-for-a-queryconfig) which can be used to invalidate the query.

```ts
const {data, queryKey} = useRouteQuery(myExampleUserRoute, 'mainQuery')
const queryClient = useQueryClient()

queryClient.invalidateQueries({queryKey})
```

Note that in the example above we are accessing a `Blocking` query, so the data is guaranteed to be available when the component is rendered. If there is no data when navigating to a route, the route transition will be blocked until the query is resolved.

Next let's see what happens when we access a `Deferred` query.

## 14. Add a deferred query to optimize HPC

Although blocking queries are the default and preferred approach for fetching data that is crucial to the user experience, we may want to defer some secondary content in order to trade a complete initial load for better [HPC](https://thehub.github.com/epd/engineering/fundamentals/performance-web-performance/#highest-priority-content-hpc).

We can add a deferred query to fetch the user's followers.

First we need to define the query in the route config.

**📄 `ui/packages/my-example/routes/user-route.ts`**

```diff
import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import {myExampleAppBuilder} from '../config/app-builder'

type MyResponse = {name: string}
+type MyDeferredResponse = Array<{id: number, name: string}>

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    mainQuery<MyResponse>(),
+   {
+     queryName: 'followers',
+     queryDeps: ({pathname}) => ({
+       pathname: `${pathname}/followers`,
+     }),
+     queryFn: async queryKey => queryFnFetch<MyDeferredResponse>(queryKey),
+     type: QueryRouteQueryType.Deferred,
+   },
  ],
})
```

Now we can access the query data in our component.

**📄 `ui/packages/my-example/routes/User.tsx`**

```diff
import {useRouteQuery} from '@github-ui/react-core/future/use-route-query'
import {useRouteParams} from '@github-ui/react-core/future/use-route-params'
import {myExampleUserRoute} from ./user-route

export const MyExampleUser: React.FC = () => {
  const {data} = useRouteQuery(myExampleUserRoute, 'mainQuery')
+ const {data: followers, isPending, isError, refetch} = useRouteQuery(myExampleUserRoute, 'followers')
  const {id} = useRouteParams(myExampleUserRoute)
  return (
    <>
      <h2>User {id}</h2>
      <p>Hello {data.name}</p>
+     <h3>Followers</h3>
+     {isError ? (
+       <p>
+         Fetching followers failed:
+         <button onClick={() => refetch()}>Retry</button>
+       </p>
+     ) : isPending ? (
+       <p>Loading...</p>
+     ) : (
+       <ul>
+         {followers.map(follower => (
+           <li key={follower.id}>{follower.name}</li>
+         ))}
+       </ul>
+     )}
    </>
  )
}
```

As the followers data is of type `Deferred`, we are forced by typescript to handle the loading state.

**Note** that when designing loading states we will have to be careful to not have content shift around as its loaded in or we will face degraded [CLS](https://thehub.github.com/epd/engineering/fundamentals/performance-web-performance/#cumulative-layout-shift-cls).

TSQ offers a lot of flexibility in how you can handle loading and error states. Read more [here](https://tanstack.com/query/latest/docs/overview#query-states).

## Congratulations!

You're done this tutorial and ready to continue building using `DataRouter` and `QueryRoute`.

### Next steps

1. Check out the [API documentation](./api/).
2. Read some [recipes](./recipes/) for how to handle common tasks.
3. Reach to the React-Platform with any questions or suggestions in [`#react` on Slack](https://github-grid.enterprise.slack.com/archives/CD1AK7VT3).
4. Leave feedback via [Slack](https://gh.io/data-router-feedback-slack) or [this discussion](https://gh.io/data-router-feedback)
