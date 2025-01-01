import type {Meta} from '@storybook/react'
import {CreateIssueForm, type CreateIssueFormProps} from './CreateIssueForm'
import {IssueCreateContextProvider} from './contexts/IssueCreateContext'
import {getDefaultConfig} from './utils/option-config'
import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'
import type {Repository} from '@github-ui/item-picker/RepositoryPicker'
import {noop} from '@github-ui/noop'
import {BrowserRouter} from 'react-router-dom'

const repository: Repository = {
  codeOfConductFileUrl: undefined,
  contributingFileUrl: undefined,
  supportFileUrl: undefined,
  databaseId: 1,
  hasIssuesEnabled: true,
  id: '1',
  isArchived: false,
  isInOrganization: false,
  isPrivate: false,
  name: 'fake-repo',
  nameWithOwner: 'fake-org/fake-repo',
  owner: {
    avatarUrl: '',
    databaseId: 1,
    login: 'fake-org',
    issueTypesEnabled: true,
  },
  planFeatures: {
    maximumAssignees: 1,
  },
  isBlankIssuesEnabled: true,
  securityPolicyUrl: undefined,
  shortDescriptionHTML: '',
  slashCommandsEnabled: false,
  viewerCanPush: false,
  viewerInteractionLimitReasonHTML: '',
  viewerIssueCreationPermissions: {
    assignable: true,
    labelable: true,
    milestoneable: true,
    triageable: true,
    typeable: true,
  },
  visibility: 'PUBLIC',
  ' $fragmentType': 'RepositoryPickerRepository',
}

const meta = {
  title: 'IssueCreate',
  component: CreateIssueForm,
  decorators: [
    (Story, _) => (
      <BrowserRouter>
        <RelayEnvironmentProvider environment={createMockEnvironment()}>
          <IssueCreateContextProvider optionConfig={getDefaultConfig()} preselectedData={{repository}}>
            <Story />
          </IssueCreateContextProvider>
        </RelayEnvironmentProvider>
      </BrowserRouter>
    ),
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    enabledFeatures: ['copilot_immersive_issue_creation_cta'],
  },
} satisfies Meta<typeof CreateIssueForm>

export default meta

const defaultArgs: CreateIssueFormProps = {
  repository,
  title: 'Issue Title',
  body: 'Issue Body',
  setTitle: noop,
  setBody: noop,
  clearOnCreate: noop,
  issueFormRef: {current: null},
  onCreateSuccess: noop,
  onCreateError: noop,
  onCancel: noop,
}

export const CreateIssueFormExample = {
  args: {
    ...defaultArgs,
  },
}

export const CreateIssueFormWithCopilotCTAExample = {
  args: {
    ...defaultArgs,
    // user must have write permissions OR be in a private/internal repo to see CTA:
    repository: {...repository, viewerCanPush: true, visibility: 'PRIVATE'},
  },
}
