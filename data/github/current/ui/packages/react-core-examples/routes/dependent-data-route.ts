import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'

type UserPayload = {
  id: string
  login: string
  avatarUrl: string
}

export const reactCoreExamplesDependentDataRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesDependentDataRoute',
  {
    path: '/_react_core_examples/dependent_data',
    queries: [
      mainQuery<UserPayload>({
        queryDeps: ({pathname, searchParams}) => ({pathname, searchParams: {login: searchParams.get('login')}}),
      }),
    ],
  },
)
