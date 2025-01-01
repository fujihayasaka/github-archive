import {reactCoreExamplesAppBuilder} from '../config/app-builder'

export const reactCoreExamplesFeatureFlagRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesFeatureFlagRoute',
  {
    path: '/_react_core_examples/feature_flag',
  },
)
