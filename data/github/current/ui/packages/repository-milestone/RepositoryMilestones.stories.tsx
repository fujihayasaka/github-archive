import type {Meta} from '@storybook/react'
import {noop} from '@github-ui/noop'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {graphql} from 'relay-runtime'

import {RepositoryMilestonesInternal} from './RepositoryMilestones'
import type {RepositoryMilestonesInternalStoryQuery} from './__generated__/RepositoryMilestonesInternalStoryQuery.graphql'

type RepositoryMilestonesQueries = {
  repositoryMilestonesQuery: RepositoryMilestonesInternalStoryQuery
}

const meta = {
  title: 'Recipes/RepositoryMilestones',
  component: RepositoryMilestonesInternal,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof RepositoryMilestonesInternal>

export default meta

const defaultArgs: Partial<typeof RepositoryMilestonesInternal> = {
  onTemplateSelected: noop,
}

export const TemplateListNewInternalExample = {
  decorators: [relayDecorator<typeof RepositoryMilestonesInternal, RepositoryMilestonesQueries>],
  args: {
    ...defaultArgs,
  },
  parameters: {
    relay: {
      queries: {
        repositoryMilestonesQuery: {
          type: 'fragment',
          query: graphql`
            query RepositoryMilestonesInternalStoryQuery @relay_test_operation {
              repository(owner: "owner", name: "name") {
                ...RepositoryMilestonesInternal @arguments(state: OPEN)
              }
            }
          `,
          variables: {},
        },
      },
      mockResolvers: {},
      mapStoryArgs: ({queryData}) => ({
        repository: queryData.repositoryMilestonesQuery.repository!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof RepositoryMilestonesInternal, RepositoryMilestonesQueries>
