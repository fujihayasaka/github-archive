import type {Meta} from '@storybook/react'
import {RepositoryMilestone} from './RepositoryMilestone'

import {createMockEnvironment} from 'relay-test-utils'
import {TestComponentRoot} from './test-utils/RepositoryMilestoneTestComponent'

const environment = createMockEnvironment()

function EntryPoint() {
  return <TestComponentRoot environment={environment} />
}

const meta = {
  title: 'Recipes/RepositoryMilestone',
  component: RepositoryMilestone,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    jest: {
      timeout: 20_000,
    },
  },
  argTypes: {},
} satisfies Meta<typeof RepositoryMilestone>

export default meta

export const RepositoryMilestoneExample = {
  args: {},
  render: () => {
    return <EntryPoint />
  },
}
