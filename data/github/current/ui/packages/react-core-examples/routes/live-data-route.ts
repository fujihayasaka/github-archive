import {mainQuery} from '@github-ui/react-core/future/main-query'

import {reactCoreExamplesAppBuilder} from '../config/app-builder'

type Label = {
  id: string
  name: string
  nameHTML: string
  color: string
  url: string
  description: string
}

type PullPayload = {
  aliveChannel: string
  pull: {
    id: string
    title: string
    url: string
    labels: Label[]
  }
}

export const reactCoreExamplesLiveDataRoute = reactCoreExamplesAppBuilder.createQueryRouteConfig(
  'reactCoreExamplesLiveDataRoute',
  {
    path: '/_react_core_examples/live_data',
    queries: [mainQuery<PullPayload>()],
  },
)
