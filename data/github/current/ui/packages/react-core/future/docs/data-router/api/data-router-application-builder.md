# `DataRouterApplicationBuilder`

📄 [`ui/packages/react-core/future/data-router-application.ts`](../../../data-router-application.ts#L31)

Class responsible for creating and configuring an app along with its routes and queries.

## `create`

Creates a `DataRouterApplicationBuilder` instance.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `appName` | `string` | The name of the application. Must match the name of the package. |

```ts
import {DataRouterApplicationBuilder} from '@github-ui/react-core/future/data-router-application'

export const myExampleAppBuilder = DataRouterApplicationBuilder.create('my-example')
```

## `createDataRouterAppFromRoutes`

Takes an array of React Router route objects and returns a `DataRouterApplication` instance that can be registered for rendering with `registerDataRouterApp`.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `routes`  | `array` | `({isEnabled}) => array` | An array of [React Router route objects](https://reactrouter.com/6.28.1/route/route) that make up the application, or a function which, when executed, returns the routes. |

```ts
import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {myExampleAppBuilder} from './config/app-builder'

export const myExampleApp = myExampleAppBuilder.createDataRouterAppFromRoutes([
  {
    path: '/example',
    Component: Layout,
    children: [
      {index: true, Component: Home},
      {path: '/example/:id', Component: Show},
    ],
  },
])
```

For brevity this example shows raw React-Router route objects, although you will probably want to use [`QueryRoute`](./query-route.md) created with [`dataRouterAppBuilder.createQueryRouteConfig`](#createqueryrouteconfig) for your routes.

Alternatively, to allow teams to control which routes are used in the application based on feature flag states, `createDataRouterAppFromRoutes` can take a function instead.

```ts
import {registerDataRouterApp} from '@github-ui/react-core/register-app'
import {myExampleAppBuilder} from './config/app-builder'

export const myExampleApp = myExampleAppBuilder.createDataRouterAppFromRoutes(({isEnabled}) => {
  if (isEnabled('my-feature-name')) {
    return [
      {
        path: '/example',
        Component: LayoutNew,
        children: [
          {index: true, Component: HomeNew},
          {path: '/example/:id', Component: ShowNew},
        ],
      },
    ]
  } else {
    return [
      {
        path: '/example',
        Component: LayoutOld,
        children: [
          {index: true, Component: HomeOld},
          {path: '/example/:id', Component: ShowOld},
        ],
      },
    ]
  }
})
```

## `createQueryRouteConfig`

Creates a [`QueryRoute`](./query-route.md) config that can be used to define the route config and queries for a route.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `routeId` | `string` | A unique identifier for the route. |
| `queryRoute` | `object` | `QueryRoute` config options. [See `QueryRoute` API docs for details](./query-route.md). |

```ts
import {queryFnFetch} from '@github-ui/react-core/future/query-fn-fetch'
import {myExampleAppBuilder} from '../config/app-builder'

type ExampleResponse = {name: string}

export const myExampleShowRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleShowRoute', {
  path: '/example/:id',
  queries: [
    {
      queryName: 'payload',
      queryDeps: ({params}) => ({pathname: `/api/users/${params.id}`}),
      queryFn: async queryKey => queryFnFetch<ExampleResponse>(queryKey),
    },
  ],
})
```
