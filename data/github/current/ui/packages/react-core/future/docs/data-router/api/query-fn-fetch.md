# `queryFnFetch`

📄 [`ui/packages/react-core/future/query-fn-fetch.ts`](/ui/packages/react-core/future/query-fn-fetch.ts)

A specialized fetch function with an API intended for use by `queryFn`s that need to make fetch requests. In addition to calling `reactFetchJSON` to add the appropriate React headers to the request, this function will also check the response status and throw a `ResponseError` if necessary, as well as hooking into `reportTraceData`.

## Usage

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `queryKey` | `object` | For ease of use, `queryFnFetch` takes the same `queryKey` argument as a [`QueryConfig.queryFn`](./query-config.md#queryfn). This allows passing the `queryKey` argument directly frothe `queryFn` to `queryFnFetch`. Note that `queryFnFetch` is only interested in the `queryKey.queryDeps`. |
| `queryKey.queryDeps` | `object` | The object returned from [`queryDeps`](./query-config.md#querydeps). this has a constrained type of `{pathname: string, searchParams?: ConstructorParameters<typeof URLSearchParams>[0], init?: JSONRequestInit}` which allows construction of a request in `queryDeps`. |
| `queryKey.queryDeps.pathname` | `string` | The path to fetch from. |
| `queryKey.queryDeps.searchParams` | `ConstructorParameters<typeof URLSearchParams>[0]` | The search params to include in the request. |
| `queryKey.queryDeps.init` | `JSONRequestInit` | This can be used to [configure additional fetch args](https://developer.mozilla.org/en-US/docs/Web/API/RequestInit) such as headers, http method, body etc. |

Here's an example of a `QueryConfig` that makes use of `queryDeps` to construct request args for `queryFnFetch`:

```ts
type ExampleResponse = {name: string}

export const myExampleUserRoute = myExampleAppBuilder.createQueryRouteConfig('myExampleUserRoute', {
  path: '/example/users/:id',
  queries: [
    {
      queryName: 'payload',
      queryDeps: ({pathname, searchParams}) => ({
        pathname,
        // only the "page" search param will be added to the `queryKey` and sent to the server.
        // We filter out any undefined or null values from the server request.
        searchParams: {
          page: searchParams.get('page'),
        },
        init: {
          method: 'POST',
          headers: {
            'X-GitHub-Custom-Header': 'example',
          },
        },
      }),
      queryFn: async queryKey => queryFnFetch<ExampleResponse>(queryKey),
    },
  ],
})
```

By preparing the request in `queryDeps`, we ensure that the `queryKey` is constructed from all arguments used to prepare the request. This is important because the `queryKey` is used as a cache key, and if the `queryKey` doesn't accurately represent the request, we may not get the data we expect.
