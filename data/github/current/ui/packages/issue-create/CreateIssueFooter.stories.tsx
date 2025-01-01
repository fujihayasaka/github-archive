import type {Meta} from '@storybook/react'
import {CreateIssueFooter} from './CreateIssueFooter'
import {noop} from '@github-ui/noop'
import {IssueCreateConfigContextProvider} from './contexts/IssueCreateConfigContext'
import {getDefaultConfig} from './utils/option-config'

const meta = {
  title: 'IssueCreate',
  component: CreateIssueFooter,
  decorators: [
    (Story, _) => (
      <IssueCreateConfigContextProvider optionConfig={getDefaultConfig()}>
        <Story />
      </IssueCreateConfigContextProvider>
    ),
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof CreateIssueFooter>

export default meta

const defaultArgs = {
  onClose: noop,
}

export const CreateIssueFooterExample = {
  args: {
    ...defaultArgs,
  },
}

export const CreateIssueFooterWithoutCreateMoreExample = {
  args: {
    ...defaultArgs,
    hideCreateMore: true,
  },
}

export const CreateIssueFooterWithoutCancelExample = {
  args: {
    ...defaultArgs,
    onClose: undefined,
  },
}
