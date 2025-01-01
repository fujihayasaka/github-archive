import type {Meta} from '@storybook/react'
import {CopilotRefineIssueDialog, CopilotRefineIssueDialogGraphQLQuery} from './CopilotRefineIssueDialog'
import {TopRepositories} from '@github-ui/item-picker/RepositoryPicker'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import type {CopilotRefineIssueDialogQuery} from './__generated__/CopilotRefineIssueDialogQuery.graphql'
import type {RepositoryPickerTopRepositoriesQuery} from '@github-ui/item-picker/RepositoryPickerTopRepositoriesQuery.graphql'

type CopilotRefineIssueDialogQueries = {
  topReposQuery: RepositoryPickerTopRepositoriesQuery
  currentRepoQuery: CopilotRefineIssueDialogQuery
}

const meta = {
  title: 'Recipes/CopilotRefineIssueDialog',
  component: CopilotRefineIssueDialog,
} satisfies Meta<typeof CopilotRefineIssueDialog>

export default meta

export const Example = {
  decorators: [relayDecorator<typeof CopilotRefineIssueDialog, CopilotRefineIssueDialogQueries>],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    relay: {
      queries: {
        topReposQuery: {
          type: 'preloaded',
          query: TopRepositories,
          variables: {topRepositoriesFirst: 5, hasIssuesEnabled: true, owner: null},
        },
        currentRepoQuery: {
          type: 'preloaded',
          query: CopilotRefineIssueDialogGraphQLQuery,
          variables: {owner: 'owner', name: 'repo'},
        },
      },
    },
  },
  argTypes: {
    onClose: {action: 'closed'},
    title: {control: 'text', defaultValue: 'Sample Issue Title'},
    markdown: {control: 'text', defaultValue: 'This is a sample markdown content for the issue.'},
    copilotApiUrl: {control: 'text', defaultValue: 'https://api.example.com'},
    owner: {control: 'text', defaultValue: 'owner'},
    repoName: {control: 'text', defaultValue: 'repo'},
  },
} satisfies RelayStoryObj<typeof CopilotRefineIssueDialog, CopilotRefineIssueDialogQueries>
