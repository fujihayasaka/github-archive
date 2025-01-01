import {
  dataRouterDecorator,
  type DataRouterMeta,
  type DataRouterStoryObj,
} from '@github-ui/react-core/future/test-utils/storybook'

import {handlers} from './__tests__/utils/handlers'
import {reactCoreExamplesApp} from './react-core-examples'
import {ReactCoreExamplesIndex} from './routes/Index'
import {reactCoreExamplesIndexRoute} from './routes/index-route'

const meta = {
  title: 'Apps/React Core Examples/App',
  component: ReactCoreExamplesIndex,
  decorators: [dataRouterDecorator],
  parameters: {
    dataRouter: {
      app: reactCoreExamplesApp,
      initialEntries: [reactCoreExamplesIndexRoute.generatePath({})],
    },
    msw: {handlers},
  },
} satisfies DataRouterMeta<typeof ReactCoreExamplesIndex>

export default meta

type ReactCoreExamplesStory = DataRouterStoryObj<typeof ReactCoreExamplesIndex>

export const Index: ReactCoreExamplesStory = {}
