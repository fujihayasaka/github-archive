import {
  dataRouterDecorator,
  type DataRouterMeta,
  type DataRouterStoryObj,
} from '@github-ui/react-core/future/test-utils/storybook'
import {accessPolicyShow} from '../routes/access-policy-show-route'
import {appBuilder} from '../config/app'
import {AccessPolicyShow} from './AccessPolicyShow'
import {mockAccessPolicyShowPayload, mockHandlers} from '../test-utils/mocks'

const routePayload = mockAccessPolicyShowPayload()
const pathname = accessPolicyShow.generatePath({org: routePayload.orgDisplayLogin})

const meta = {
  title: 'Apps/GitHub Models org settings/AccessPolicyShow',
  component: AccessPolicyShow,
  decorators: [dataRouterDecorator],
  parameters: {
    dataRouter: {
      app: appBuilder.createDataRouterAppFromRoutes([accessPolicyShow.toRoute({Component: AccessPolicyShow})]),
      initialEntries: [pathname],
      embeddedData: {meta: {}, payload: {[accessPolicyShow.id]: routePayload}},
    },
    msw: {handlers: mockHandlers({pathname, type: 'success'})},
  },
} satisfies DataRouterMeta<typeof AccessPolicyShow>

export default meta

export const Example: DataRouterStoryObj<typeof AccessPolicyShow> = {}
