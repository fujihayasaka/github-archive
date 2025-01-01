# How to choose a data fetching strategy

There are lots of options for how to fetch data in your React app. This guide will help you choose which strategy to use.

<!-- prettier-ignore -->
| The approach | Why you might use this | Example | Client conventions | Server conventions |
| :--- | :--- | :--- | :--- | :--- |
| `QueryRoute` with `Blocking` data | The data is coupled to its route. The data is crucial to the primary user experience. The data is necessary to render HPC | Fetching the title and description of a PR | TODO Access via `useRouteQuery` | Pass the payload into `render_react_app` |
| `QueryRoute` with `Deferred` data | The data is coupled to its route. The data is too expensive to fetch as initial data. The data is not necessary to render the HPC | Fetching the comments on an issue | TODO Access via `useRouteQuery` | Pass the payload _proc_ into `render_react_app` |
| Custom route deferred data | The data is not coupled to a route. The data is not necessary to render the HPC. The data is coupled to a resource that shared between routes. You might have some custom data store | ??? | TODO Write a query in the route registration Access via `useRouteQuery` | Create your own controller/action |
| Manually fetched data | Data should not be fetched until a particular user interaction | Fetching autocomplete suggestions | Call `useQuery` in your component | Create your own controller/action |
