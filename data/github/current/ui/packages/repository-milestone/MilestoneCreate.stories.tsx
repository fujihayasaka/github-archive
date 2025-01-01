import type {Meta} from '@storybook/react'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {graphql} from 'relay-runtime'
import {storyWrapper} from '@github-ui/react-core/test-utils'

import {MilestoneCreate} from './MilestoneCreate'
import type {MilestoneCreateRepositoryStoryQuery} from './__generated__/MilestoneCreateRepositoryStoryQuery.graphql'
import {noop} from '@github-ui/noop'

type MilestoneCreateQueries = {
  repositoryMilestonesNewQuery: MilestoneCreateRepositoryStoryQuery
}

const meta = {
  title: 'Recipes/MilestoneCreate',
  component: MilestoneCreate,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof MilestoneCreate>

export default meta

const defaultArgs: Partial<typeof MilestoneCreate> = {
  onTemplateSelected: noop,
}

export const MilestoneCreateExample = {
  decorators: [relayDecorator<typeof MilestoneCreate, MilestoneCreateQueries>, storyWrapper()],
  args: {
    ...defaultArgs,
  },
  parameters: {
    relay: {
      queries: {
        repositoryMilestonesNewQuery: {
          type: 'fragment',
          query: graphql`
            query MilestoneCreateRepositoryStoryQuery @relay_test_operation {
              repository(owner: "owner", name: "name") {
                ...MilestoneCreateFormRepositoryQuery
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
        }),
      },
      mapStoryArgs: ({queryData}) => ({
        repository: queryData.repositoryMilestonesNewQuery.repository!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof MilestoneCreate, MilestoneCreateQueries>
