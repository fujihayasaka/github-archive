import type {Meta} from '@storybook/react'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {graphql} from 'relay-runtime'
import {storyWrapper} from '@github-ui/react-core/test-utils'

import {MilestoneEdit} from './MilestoneEdit'
import type {MilestoneEditStoryQuery} from './__generated__/MilestoneEditStoryQuery.graphql'

type MilestoneEditQueries = {
  repositoryMilestoneEditQuery: MilestoneEditStoryQuery
}

const meta = {
  title: 'Recipes/MilestoneEdit',
  component: MilestoneEdit,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof MilestoneEdit>

export default meta

export const MilestoneEditExample = {
  decorators: [relayDecorator<typeof MilestoneEdit, MilestoneEditQueries>, storyWrapper()],
  args: {},
  parameters: {
    relay: {
      queries: {
        repositoryMilestoneEditQuery: {
          type: 'fragment',
          query: graphql`
            query MilestoneEditStoryQuery @relay_test_operation {
              repository(owner: "owner", name: "name") {
                ...MilestoneEditFormRepositoryQuery @arguments(number: 1)
              }
            }
          `,
          variables: {},
        },
      },
      mockResolvers: {
        Repository: () => ({
          nameWithOwner: 'owner/name',
          viewerCanPush: true,
          id: 'repo-123',
          milestone: {
            id: 'milestone-123',
            title: 'v1.0 Release',
            description: 'First major release',
            dueOn: '2026-08-30T00:00:00Z',
          },
        }),
      },
      mapStoryArgs: ({queryData}) => ({
        repository: queryData.repositoryMilestoneEditQuery.repository!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof MilestoneEdit, MilestoneEditQueries>
