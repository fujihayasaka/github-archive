import {
  dataRouterDecorator,
  type DataRouterMeta,
  type DataRouterStoryObj,
} from '@github-ui/react-core/future/test-utils/storybook'

import {getReactSandboxFutureIndexRoutePayload} from '../__tests__/utils/mock-data'
import {handlers} from '../__tests__/utils/mock-server/handlers'
import {reactSandboxFutureAppBuilder} from '../config/app-builder'
import {reactSandboxFutureIdRoute} from '../routes/id-route'
import {reactSandboxFutureIndexRoute} from '../routes/index-route'
import {DisplayQueries} from './DisplayQueries'

type DisplayQueriesStory = DataRouterStoryObj<typeof DisplayQueries>

const meta = {
  title: 'Apps/React Sandbox Future/DisplayQueries',
  component: DisplayQueries,
  decorators: [dataRouterDecorator],
  args: {route: reactSandboxFutureIndexRoute, title: 'Example Title'},
  parameters: {
    dataRouter: {
      app: (Story, context) =>
        reactSandboxFutureAppBuilder.createDataRouterAppFromRoutes([
          context.args.route.toRoute({
            Component: () => <Story />,
          }),
        ]),
      initialEntries: [reactSandboxFutureIndexRoute.generatePath({})],
      embeddedData: getReactSandboxFutureIndexRoutePayload(false),
    },
    msw: {handlers},
  },
} satisfies DataRouterMeta<typeof DisplayQueries>

export default meta

export const IndexRouteQueries: DisplayQueriesStory = {}

export const IndexRouteQueriesNoTitle: DisplayQueriesStory = {
  args: {title: undefined},
}

export const IdRouteQueries: DisplayQueriesStory = {
  args: {route: reactSandboxFutureIdRoute, title: 'Example Title'},
  parameters: {
    dataRouter: {
      initialEntries: [reactSandboxFutureIdRoute.generatePath({id: '123'})],
    },
  },
}
