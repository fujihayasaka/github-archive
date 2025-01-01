import type {Meta, StoryObj} from '@storybook/react'

import {ExpandedChecksList} from './ExpandedChecksList'
import type {ComponentProps} from 'react'
import {StatusCheckGenerator} from '../../../test-utils/object-generators/status-check'

const meta: Meta<typeof ExpandedChecksList> = {
  title: 'Pull Requests/Merge Box/ExpandedChecksList',
  component: ExpandedChecksList,
}
export default meta

const props: ComponentProps<typeof ExpandedChecksList> = {
  pullRequestId: 'PR_456789',
  statusRollupSummary: [
    {count: 1, state: 'FAILURE'},
    {count: 1, state: 'PENDING'},
    {count: 5, state: 'IN_PROGRESS'},
    {count: 1, state: 'SUCCESS'},
  ],
  statusChecks: [
    StatusCheckGenerator({state: 'FAILURE'}),
    StatusCheckGenerator({state: 'PENDING'}),
    StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-34 (push)'}),
    StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-4 (push)'}),
    StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-35 (push)'}),
    StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-6 (push)'}),
    StatusCheckGenerator({state: 'IN_PROGRESS', displayName: 'github-ruby-next-5 (push)'}),
    StatusCheckGenerator({state: 'SUCCESS'}),
  ],
}

export const List: StoryObj<{name: string}> = {
  render: () => <ExpandedChecksList {...props} />,
}
