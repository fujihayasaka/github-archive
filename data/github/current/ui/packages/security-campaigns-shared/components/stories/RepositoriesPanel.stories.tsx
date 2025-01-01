import type {Meta} from '@storybook/react'
import {RepositoriesPanel, type RepositoriesPanelProps} from '../RepositoriesPanel'
import {Title, Controls} from '@storybook/blocks'

const meta = {
  title: 'Security Campaigns Shared/Repositories panel',
  component: RepositoriesPanel,
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
} satisfies Meta<typeof RepositoriesPanel>

export default meta

const defaultArgs: Partial<RepositoriesPanelProps> = {
  alertsSummary: {
    repositories: [
      {
        repository: {
          name: 'octodemo',
          ownerLogin: 'github',
          typeIcon: 'lock',
        },
        alertCount: 50,
      },
      {
        repository: {
          name: 'octocat',
          ownerLogin: 'github',
          typeIcon: 'lock',
        },
        alertCount: 70,
      },
    ],
  },
  isSummaryPending: false,
  error: null,
}

export const RepositoriesPanelDefault = {
  args: defaultArgs,
  render: (args: RepositoriesPanelProps) => <RepositoriesPanel {...args} />,
}

export const RepositoriesPanelLoading = {
  args: {
    ...defaultArgs,
    isSummaryPending: true,
  },
  render: (args: RepositoriesPanelProps) => <RepositoriesPanel {...args} />,
}

export const RepositoriesPanelError = {
  args: {
    ...defaultArgs,
    error: new Error('Something went wrong'),
    alertsSummary: undefined,
  },
  render: (args: RepositoriesPanelProps) => <RepositoriesPanel {...args} />,
}
