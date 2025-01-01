# `useRouteParams`

Provides a wrapper around [`useParams` from React Router](https://reactrouter.com/6.28.2/hooks/use-params) API that provides type-safe access to route params.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `queryRoute` | `QueryRoute` instance | The `QueryRoute` on which the query is defined. Type information about the query, including the shape of the `data` as well as if the query is `Deferred` or `Blocking` can be inferred. |

```tsx
import {useRouteParams} from '@github-ui/react-core/future/use-route-params'
import {showRoute} from './show-route'

export const Show() {
  const {id} = useRouteParams(showRoute)

  return (
    <>
      <h2>{`id: ${id}`}</h2>
    </>
  )
}
```
