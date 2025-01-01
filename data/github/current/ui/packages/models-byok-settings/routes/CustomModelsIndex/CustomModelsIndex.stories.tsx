import {
  dataRouterDecorator,
  type DataRouterMeta,
  type DataRouterStoryObj,
} from '@github-ui/react-core/future/test-utils/storybook'

import {modelsByokSettingsAppBuilder} from '../../config/app-builder'
import {mockCustomModelsIndexPayload} from '../../test-utils/mocks'
import {customModelsIndexRoute} from './custom-models-index-route'
import {CustomModelsIndex} from './CustomModelsIndex'

const routePayload = mockCustomModelsIndexPayload({customKeys: []})
const pathname = customModelsIndexRoute.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/Models BYOK settings/CustomModelsIndex',
  component: CustomModelsIndex,
  decorators: [dataRouterDecorator],
  parameters: {
    dataRouter: {
      app: modelsByokSettingsAppBuilder.createDataRouterAppFromRoutes([
        customModelsIndexRoute.toRoute({Component: CustomModelsIndex}),
      ]),
      initialEntries: [pathname],
      embeddedData: {payload: {[customModelsIndexRoute.id]: routePayload}},
    },
  },
} satisfies DataRouterMeta<typeof CustomModelsIndex>

export default meta

export const Default: DataRouterStoryObj<typeof CustomModelsIndex> = {}

export const WithModels: DataRouterStoryObj<typeof CustomModelsIndex> = {
  parameters: {
    dataRouter: {
      embeddedData: {
        payload: {
          [customModelsIndexRoute.id]: mockCustomModelsIndexPayload(),
        },
      },
    },
  },
}
