import type {ComponentProps} from 'react'
import type {Meta} from '@storybook/react'
import {Wrapper} from '@github-ui/react-core/test-utils'
import {RequestTypeProvider} from '../contexts/RequestTypeContext'
import {NewExemptionRequestPage} from './NewExemptionRequestPage'
import type {NewExemptionRequestPayload, RequestType} from '../delegated-bypass-types'
import {ruleSuite} from '../__tests__/helpers'

type ExemptionRequestPageProps = ComponentProps<typeof NewExemptionRequestPage>
type WrappedComponentProps = ExemptionRequestPageProps &
  NewExemptionRequestPayload & {
    requestType: RequestType
  }

const meta = {
  title: 'Apps/DelegatedBypass/NewExemptionRequest',
  component: NewExemptionRequestPage,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
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
  ruleSuite,
  hasPostApprovalAction: false,
  requestType: 'push_ruleset_bypass',
}

export const Default = {
  args: defaultArgs,
  render: (args: WrappedComponentProps) => <WrappedComponent {...args} />,
}

const WrappedComponent = ({requestType, ...args}: WrappedComponentProps) => (
  <Wrapper routePayload={args}>
    <RequestTypeProvider requestType={requestType}>
      <NewExemptionRequestPage />
    </RequestTypeProvider>
  </Wrapper>
)
