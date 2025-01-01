import type {Meta, StoryObj} from '@storybook/react'

import {PageDataContextProvider} from '@github-ui/pull-request-page-data-tooling/page-data-context'
import {BASE_PAGE_DATA_URL} from '@github-ui/pull-request-page-data-tooling/render-with-query-client'
import type {ComponentProps} from 'react'
import {StatusCheckGenerator} from '../../../test-utils/object-generators/status-check'
import {ExpandedChecksList} from './ExpandedChecksList'

const meta: Meta<typeof ExpandedChecksList> = {
  title: 'Pull Requests/Merge Box/ExpandedChecksList',
  component: ExpandedChecksList,
  decorators: [
    Story => (
      <div style={{maxWidth: '800px'}}>
        <PageDataContextProvider basePageDataUrl={BASE_PAGE_DATA_URL}>
          <Story />
        </PageDataContextProvider>
      </div>
    ),
  ],
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
  mergeBoxUserPreferences: {
    statusChecksGrouping: 'grouped_by_status',
  },
}

export const List: StoryObj<{name: string}> = {
  render: () => <ExpandedChecksList {...props} />,
}
