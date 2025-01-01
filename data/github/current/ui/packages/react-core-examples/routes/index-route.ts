import {reactCoreExamplesAppBuilder} from '../config/app-builder'

export const reactCoreExamplesIndexRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesIndexRoute',
  {
    path: '/_react_core_examples',
    index: true,
  },
)
