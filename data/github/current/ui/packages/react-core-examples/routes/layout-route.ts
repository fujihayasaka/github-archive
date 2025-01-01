import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'

type LayoutPayload = {
  login: string
}

export const reactCoreExamplesLayoutRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesLayoutRoute',
  {
    path: '/_react_core_examples',
    queries: [
      mainQuery<LayoutPayload>({
        queryDeps: ({pathname}) => ({pathname: `${pathname}/layout`}),
      }),
    ],
  },
)
