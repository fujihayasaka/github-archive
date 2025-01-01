import {registerDataRouterApp} from '@github-ui/react-core/register-app'

import {reactCoreExamplesAppBuilder} from './config/app-builder'
import {reactCoreExamplesDependentDataRoute} from './routes/dependent-data-route'
import {ReactCoreExamplesDependentData} from './routes/DependentData'
import {reactCoreExamplesEnrichedDataRoute} from './routes/enriched-data-route'
import {ReactCoreExamplesEnrichedData} from './routes/EnrichedData'
import {reactCoreExamplesFeatureFlagRoute} from './routes/feature-flag-route'
import {ReactCoreExamplesFeatureFlagDisabled} from './routes/FeatureFlagDisabled'
import {ReactCoreExamplesFeatureFlagEnabled} from './routes/FeatureFlagEnabled'
import {ReactCoreExamplesIndex} from './routes/Index'
import {reactCoreExamplesIndexRoute} from './routes/index-route'
import {ReactCoreExamplesLayout} from './routes/Layout'
import {reactCoreExamplesLayoutRoute} from './routes/layout-route'
import {reactCoreExamplesLiveDataRoute} from './routes/live-data-route'
import {LiveData} from './routes/LiveData'
import {Mutations} from './routes/Mutations'
import {reactCoreExamplesMutationsRoute} from './routes/mutations-route'
import {
  reactCoreExamplesNestedErrorLayoutRoute,
  reactCoreExamplesNestedLoaderErrorRoute,
  reactCoreExamplesNestedRenderErrorRoute,
} from './routes/nested-error-routes'
import {
  NestedErrorLayout,
  NestedLoaderError,
  NestedLoaderErrorBoundary,
  NestedRenderError,
  NestedRenderErrorBoundary,
} from './routes/NestedError'
import {ReactCoreExamplesPagination} from './routes/Pagination'
import {reactCoreExamplesPaginationRoute} from './routes/pagination-route'
import {reactCoreExamplesSharedComponentsRoute} from './routes/shared-components-route'
import {SharedComponents} from './routes/SharedComponents'

const routesWithFlaggedRoute = [
  reactCoreExamplesLayoutRoute.toRoute({
    Component: ReactCoreExamplesLayout,
    children: [
      reactCoreExamplesIndexRoute.toRoute({Component: ReactCoreExamplesIndex}),
      reactCoreExamplesDependentDataRoute.toRoute({Component: ReactCoreExamplesDependentData}),
      reactCoreExamplesEnrichedDataRoute.toRoute({Component: ReactCoreExamplesEnrichedData}),
      reactCoreExamplesFeatureFlagRoute.toRoute({Component: ReactCoreExamplesFeatureFlagEnabled}),
      reactCoreExamplesLiveDataRoute.toRoute({Component: LiveData}),
      reactCoreExamplesMutationsRoute.toRoute({Component: Mutations}),
      reactCoreExamplesPaginationRoute.toRoute({Component: ReactCoreExamplesPagination}),
      reactCoreExamplesSharedComponentsRoute.toRoute({Component: SharedComponents}),
      reactCoreExamplesNestedErrorLayoutRoute.toRoute({
        Component: NestedErrorLayout,
        children: [
          reactCoreExamplesNestedLoaderErrorRoute.toRoute({
            Component: NestedLoaderError,
            ErrorBoundary: NestedLoaderErrorBoundary,
          }),
          reactCoreExamplesNestedRenderErrorRoute.toRoute({
            Component: NestedRenderError,
            ErrorBoundary: NestedRenderErrorBoundary,
          }),
        ],
      }),
    ],
  }),
]

const routes = [
  reactCoreExamplesLayoutRoute.toRoute({
    Component: ReactCoreExamplesLayout,
    children: [
      reactCoreExamplesIndexRoute.toRoute({Component: ReactCoreExamplesIndex}),
      reactCoreExamplesDependentDataRoute.toRoute({Component: ReactCoreExamplesDependentData}),
      reactCoreExamplesEnrichedDataRoute.toRoute({Component: ReactCoreExamplesEnrichedData}),
      reactCoreExamplesFeatureFlagRoute.toRoute({Component: ReactCoreExamplesFeatureFlagDisabled}),
      reactCoreExamplesLiveDataRoute.toRoute({Component: LiveData}),
      reactCoreExamplesMutationsRoute.toRoute({Component: Mutations}),
      reactCoreExamplesPaginationRoute.toRoute({Component: ReactCoreExamplesPagination}),
      reactCoreExamplesSharedComponentsRoute.toRoute({Component: SharedComponents}),
      reactCoreExamplesNestedErrorLayoutRoute.toRoute({
        Component: NestedErrorLayout,
        children: [
          reactCoreExamplesNestedLoaderErrorRoute.toRoute({
            Component: NestedLoaderError,
            ErrorBoundary: NestedLoaderErrorBoundary,
          }),
          reactCoreExamplesNestedRenderErrorRoute.toRoute({
            Component: NestedRenderError,
            ErrorBoundary: NestedRenderErrorBoundary,
          }),
        ],
      }),
    ],
  }),
]

export const reactCoreExamplesApp = reactCoreExamplesAppBuilder.createDataRouterAppFromRoutes(params => {
  if (params.isEnabled('react_core_examples_feature_flag')) {
    return routesWithFlaggedRoute
  }
  return routes
})
registerDataRouterApp(reactCoreExamplesApp)
