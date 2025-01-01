import {
  dataRouterDecorator,
  type DataRouterMeta,
  type DataRouterStoryObj,
} from '@github-ui/react-core/future/test-utils/storybook'
import {http, HttpResponse} from 'msw'

import {handlers} from './__tests__/utils/mock-server/handlers'
import {reactSandboxFutureApp} from './react-sandbox-future'
import {reactSandboxFutureIdRoute} from './routes/id-route'
import {ReactSandboxFutureIndex} from './routes/Index'
import {reactSandboxFutureIndexRoute} from './routes/index-route'

const meta = {
  title: 'Apps/React Sandbox Future/App',
  component: ReactSandboxFutureIndex,
  decorators: [dataRouterDecorator],
  parameters: {
    dataRouter: {
      app: reactSandboxFutureApp,
      initialEntries: [reactSandboxFutureIndexRoute.generatePath({})],
    },
    msw: {handlers},
  },
} satisfies DataRouterMeta<typeof ReactSandboxFutureIndex>

export default meta

type ReactSandboxFutureStory = DataRouterStoryObj<typeof ReactSandboxFutureIndex>

const indexPayload = {
  meta: {},
  payload: {
    reactSandboxFutureIndexRoute: {
      someField: 'Different Data',
    },
  },
}

export const Index: ReactSandboxFutureStory = {}

export const IndexWithDifferentData: ReactSandboxFutureStory = {
  parameters: {
    dataRouter: {
      embeddedData: indexPayload,
    },
    msw: {
      handlers: [
        http.get(reactSandboxFutureIndexRoute.generatePath({}), () => HttpResponse.json(indexPayload)),
        ...handlers,
      ],
    },
  },
}

export const Id: ReactSandboxFutureStory = {
  parameters: {
    dataRouter: {
      initialEntries: [reactSandboxFutureIdRoute.generatePath({id: '1'})],
    },
  },
}
