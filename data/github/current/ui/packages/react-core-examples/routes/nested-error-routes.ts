import {QueryRouteQueryType} from '@github-ui/react-core/future/data-router-types'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'

export const reactCoreExamplesNestedRenderErrorRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesNestedRenderErrorRoute',
  {
    path: '/_react_core_examples/nested-error/render-error',
  },
)

export const reactCoreExamplesNestedErrorLayoutRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesNestedErrorLayoutRoute',
  {
    path: '/_react_core_examples/nested-error',
  },
)

export const reactCoreExamplesNestedLoaderErrorRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesNestedLoaderErrorRoute',
  {
    path: '/_react_core_examples/nested-error/loader-error',
    queries: [
      {
        queryName: 'mainQuery',
        queryFn: () => {
          throw new Error('This is a test error')
        },
        type: QueryRouteQueryType.Blocking,
      },
    ],
  },
)
