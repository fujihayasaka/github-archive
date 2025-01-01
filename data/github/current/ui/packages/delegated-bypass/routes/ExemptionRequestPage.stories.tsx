import type {ComponentProps} from 'react'
import type {Meta} from '@storybook/react'
import {HttpResponse, http} from 'msw'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {RequestTypeProvider} from '../contexts/RequestTypeContext'
import {ExemptionRequestPage} from './ExemptionRequestPage'
import type {ExemptionRequestPayload, RequestType} from '../delegated-bypass-types'
import {collaborator, exampleRequest, monalisaUser, ruleSuite} from '../__tests__/helpers'
import {FlashBanner} from '../components/FlashBanner'
import {DelegatedBypassBannersProvider} from '../contexts/DelegatedBypassBannerContext'

type ExemptionRequestPageProps = ComponentProps<typeof ExemptionRequestPage>
type WrappedComponentProps = ExemptionRequestPageProps &
  ExemptionRequestPayload & {
    requestType: RequestType
  }

const meta = {
  title: 'Apps/DelegatedBypass/ExemptionRequest',
  component: ExemptionRequestPage,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    msw: {
      handlers: [
        // handles the approve/deny request to
        // be able to show the flash banner
        http.put(`/iframe.html`, () => {
          return HttpResponse.json({})
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
    hasPostApprovalAction: {
      default: false,
      control: {type: 'boolean'},
    },
  },
} satisfies Meta<WrappedComponentProps>

export default meta

const defaultArgs: WrappedComponentProps = {
  ruleSuite: {
    ...ruleSuite,
    actor: collaborator,
  },
  responses: [],
  hasPostApprovalAction: false,
  request: {
    ...exampleRequest,
    requester: collaborator,
    requesterComment: 'Bypass please',
  },
  requestType: 'push_ruleset_bypass',
  enterprise: false,
  actionsEnabled: false,
}

const bypasserArgs: WrappedComponentProps = {
  ...defaultArgs,
  reviewer: {
    isValid: true,
    hasUndismissedReview: false,
    login: monalisaUser.login,
    isRequester: false,
  },
}

export const Bypasser = {
  args: bypasserArgs,
  render: (args: WrappedComponentProps) => <WrappedComponent {...args} />,
}

const requesterArgs: WrappedComponentProps = {
  ...defaultArgs,
  reviewer: {
    isValid: false,
    hasUndismissedReview: false,
    login: collaborator.login,
    isRequester: true,
  },
}

export const Requester = {
  args: requesterArgs,
  render: (args: WrappedComponentProps) => <WrappedComponent {...args} />,
}

const viewerArgs: WrappedComponentProps = {
  ...defaultArgs,
  ruleSuite,
  request: {
    ...exampleRequest,
    requester: monalisaUser,
    requesterComment: 'Bypass please',
  },
  reviewer: {
    isValid: false,
    hasUndismissedReview: false,
    login: collaborator.login,
    isRequester: false,
  },
}

export const Viewer = {
  args: viewerArgs,
  render: (args: WrappedComponentProps) => <WrappedComponent {...args} />,
}

const WrappedComponent = ({requestType, ...args}: WrappedComponentProps) => (
  <Wrapper routePayload={args}>
    <DelegatedBypassBannersProvider>
      <FlashBanner />
      <RequestTypeProvider requestType={requestType}>
        <ExemptionRequestPage />
      </RequestTypeProvider>
    </DelegatedBypassBannersProvider>
  </Wrapper>
)
