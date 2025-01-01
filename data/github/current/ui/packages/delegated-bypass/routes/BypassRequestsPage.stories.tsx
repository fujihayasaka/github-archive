import type {ComponentProps} from 'react'
import type {Meta} from '@storybook/react'
import {HttpResponse, http} from 'msw'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {RequestTypeProvider} from '../contexts/RequestTypeContext'
import {BypassRequestsPage} from './BypassRequestsPage'
import type {BypassRequestsRoutePayload, RequestType} from '../delegated-bypass-types'
import {
  collaborator,
  monalisaUser,
  baseExemptionUrl,
  exampleRequest,
  approvedRequest,
  deniedRequest,
} from '../__tests__/helpers'

type BypassRequestsPageProps = ComponentProps<typeof BypassRequestsPage>
type WrappedComponentProps = BypassRequestsPageProps &
  BypassRequestsRoutePayload & {
    requestType: RequestType
  }

const meta = {
  title: 'Apps/DelegatedBypass/BypassRequests',
  component: BypassRequestsPage,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        http.get(`/bypass_requests/requesters`, () => {
          return HttpResponse.json({actors: [collaborator]})
        }),
        http.get(`/bypass_requests/approvers`, () => {
          return HttpResponse.json({
            actors: [monalisaUser],
          })
        }),
      ],
    },
  },
  argTypes: {
    requestType: {
      options: [
        'push_ruleset_bypass',
        'secret_scanning',
        'repository_policy_ruleset_bypass',
        'secret_scanning_closure',
      ],
      control: {type: 'radio'},
    },
    sourceType: {
      options: ['enterprise', 'organization', 'repository'],
      control: {type: 'radio'},
    },
  },
} satisfies Meta<WrappedComponentProps>

export default meta

const defaultArgs: WrappedComponentProps = {
  exemptionRequests: [exampleRequest, approvedRequest, deniedRequest],
  filter: {},
  hasMoreRequests: false,
  baseExemptionUrl,
  sourceType: 'repository',
  requestType: 'push_ruleset_bypass',
}

export const Default = {
  args: defaultArgs,
  render: (args: WrappedComponentProps) => <WrappedComponent {...args} />,
}

const WrappedComponent = ({requestType, ...args}: WrappedComponentProps) => (
  <Wrapper routePayload={args}>
    <RequestTypeProvider requestType={requestType}>
      <BypassRequestsPage />
    </RequestTypeProvider>
  </Wrapper>
)
