import type {Meta} from '@storybook/react'
import {CreateBranchDialog, type CreateBranchDialogProps} from '../CreateBranchDialog'
import {Title, Controls} from '@storybook/blocks'
import type {ReactNode} from 'react'
import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'
import {TestWrapper} from '../../test-utils/TestWrapper'

const meta = {
  title: 'Security Campaigns Shared/Create Branch Dialog',
  component: CreateBranchDialog,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    docs: {
      page: () => (
        <>
          <Title />
          <Controls />
        </>
      ),
    },
  },
  argTypes: {},
} satisfies Meta<typeof CreateBranchDialog>
const environment = createMockEnvironment()

export default meta

const defaultArgs: Partial<CreateBranchDialogProps> = {
  alertNumbers: [1],
  alertNumbersWithSuggestedFixes: [1],
  firstAlertWithSuggestedFixTitle: 'Code injection',
  repository: {
    name: 'security-campaigns',
    typeIcon: 'repo',
    ownerLogin: 'github',
    path: '/github/security-campaigns',
  },
  createPath: '',
  onClose: () => {},
  someSelectedAlertsAreClosed: false,
  branchType: 'new',
  isCampaign: true,
}

function CreateBranchDialogStoryWrapper({children}: {children: ReactNode}) {
  return (
    <TestWrapper>
      <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
    </TestWrapper>
  )
}

export const SingleAlertCreateBranchDialog = {
  args: defaultArgs,
  render: (args: CreateBranchDialogProps) => (
    <CreateBranchDialogStoryWrapper>
      <CreateBranchDialog {...args} />
    </CreateBranchDialogStoryWrapper>
  ),
}

export const MultipleAlertsCreateBranchDialog = {
  args: {
    ...defaultArgs,
    alertNumbers: [1, 2, 3],
    alertNumbersWithSuggestedFixes: [1, 2, 3],
  },
  render: (args: CreateBranchDialogProps) => (
    <CreateBranchDialogStoryWrapper>
      <CreateBranchDialog {...args} />
    </CreateBranchDialogStoryWrapper>
  ),
}

export const ClosedAlertsCreateBranchDialog = {
  args: {
    ...defaultArgs,
    someSelectedAlertsAreClosed: true,
  },
  render: (args: CreateBranchDialogProps) => (
    <CreateBranchDialogStoryWrapper>
      <CreateBranchDialog {...args} />
    </CreateBranchDialogStoryWrapper>
  ),
}

export const AutofixCreateBranchDialog = {
  args: {
    ...defaultArgs,
    isCampaign: false,
  },
  render: (args: CreateBranchDialogProps) => (
    <CreateBranchDialogStoryWrapper>
      <CreateBranchDialog {...args} />
    </CreateBranchDialogStoryWrapper>
  ),
}
