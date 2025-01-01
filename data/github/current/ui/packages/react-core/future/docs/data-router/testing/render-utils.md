# Testing `DataRouter` with `Render` Utils

The `Render` testing utils provide a convenient way to test `DataRouter` components in your React applications. This guide will walk you through the process of writing tests for `DataRouter` using these utilities.

## API

### `render`

Renders an application given an app registration entry.

<!-- prettier-ignore -->
| Arguments | Type | Description |
| --- | --- | --- |
| `app` | `DataRouterApplication<string>` | The application to render. |
| `pathOrRouterOptions` | `string \| string[] \| RouterOptionsWithEntries` | The initial path or router options. |
| `options` | `RenderDataRouterAppOptions` | Additional options for rendering. |

#### Arguments

- `app`: The application to render. This should be a `DataRouterApplication` instance.
- `pathOrRouterOptions`: The initial path or router options. This can be a string, an array of strings, or an object with `initialEntries` and `initialIndex`.
- `options`: Additional options for rendering. This includes `userEventOptions`, `appPayload`, `embeddedData`, and `profiler`.

#### Returns

- An object with the rendered result and a `user` instance for testing user interactions.

### Example

```ts
import {render} from '@github-ui/react-core/future/test-utils/render'
// This is a `DataRouter` AppBuilder type.
import {reactSandboxFutureApp} from '../react-sandbox-future'

// Notice how we pass in a URL that matches to the route owned by the app.
const {user} = await render(reactSandboxFutureApp, '/_react_sandbox_future')

// `user` can be used to perform events on the rendered app.
user.click(screen.getByRole('link', {name: /ReactSandboxFutureId: id=1/}))
```

## Setup

If your route relies on data being fetched from rails, you can use `msw` to mock the server responses. This allows you to simulate different scenarios and test how your component behaves under various conditions upon loading.

### Mocking payloads and `msw` setup

You can setup a mock server that accepts requests for the routes you want to test. For example, if you have a route `/your-app-url-here/1` that fetches data from the server, you can mock the server response like this:

```tsx
const server = setupServer(
  http.get('/your-app-url-here/:id', ({params}) => {
    const {id} = params
    if (id === '1') {
      return HttpResponse.json({
        body: 'Response from server for id 1',
      })
    }

    return HttpResponse.json({
      body: 'Hello from server',
    })
  }),
)
```

This can be used for both blocking and deferred queries.

## Testing `DataRouter` pages

`DataRouter` is similar to testing a react component. The `Render` utils provide a convenient way to render your components and perform assertions on them.

Here is an example of how to write a test for a `DataRouter` page:

```tsx
// Mocking out response payloads for our blocking and deferred queries
const server = setupServer(
  http.get('/_react_sandbox_future', () => {
    const response = {
      body: 'Hello from index',
    }
    return HttpResponse.json(response)
  }),

  http.get('/_react_sandbox_future/:id', ({params}) => {
    const { id } = params;
    if (id === '1') {
      return HttpResponse.json({body: 'Hello from route with id 1'})
    }
    return HttpResponse.json({body: 'Hello from id route'})
  }),
)

describe('ReactSandboxFutureApp', () => {
  // These are needed to clean up the server after each test
  beforeAll(() => server.listen())
  afterEach(() => server.resetHandlers())
  afterAll(() => server.close())

  test('can test the registered app with route /1', async () => {
    // Notice that `reactSandboxFutureApp` is a `DataRouter` AppBuilder type.
    const {user} = await render(reactSandboxFutureApp, ['/_react_sandbox_future/1'])

    expect(await screen.findByText(/Hello from route with id 1/)).toBeInTheDocument()
    expect(screen.queryByText(/Hello from id route/)).not.toBeInTheDocument()
    expect(RouteContext.location).toEqual(
      expect.objectContaining({
        pathname: '/_react_sandbox_future/1',
      }),
    )
  })
})
```
