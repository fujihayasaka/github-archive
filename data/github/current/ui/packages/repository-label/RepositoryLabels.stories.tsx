import type {Meta} from '@storybook/react'
import {noop} from '@github-ui/noop'
import {relayDecorator, type RelayStoryObj} from '@github-ui/relay-test-utils/storybook'
import {graphql} from 'relay-runtime'
import {MemoryRouter} from 'react-router-dom'

import {RepositoryLabelsInternal} from './RepositoryLabels'
import type {RepositoryLabelsInternalStoryQuery} from './__generated__/RepositoryLabelsInternalStoryQuery.graphql'

type RepositoryLabelsQueries = {
  repositoryLabelsQuery: RepositoryLabelsInternalStoryQuery
}

const meta = {
  title: 'Recipes/RepositoryLabels',
  component: RepositoryLabelsInternal,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof RepositoryLabelsInternal>

export default meta

const defaultArgs: Partial<typeof RepositoryLabelsInternal> = {
  onTemplateSelected: noop,
}

export const LabelsList = {
  decorators: [
    Story => (
      <MemoryRouter>
        <Story />
      </MemoryRouter>
    ),
    relayDecorator<typeof RepositoryLabelsInternal, RepositoryLabelsQueries>,
  ],
  args: {
    ...defaultArgs,
  },
  parameters: {
    a11y: {
      test: 'todo',
    },
    relay: {
      queries: {
        repositoryLabelsQuery: {
          type: 'fragment',
          query: graphql`
            query RepositoryLabelsInternalStoryQuery @relay_test_operation {
              repository(owner: "owner", name: "name") {
                ...RepositoryLabelsInternal @arguments(skip: 0)
              }
            }
          `,
          variables: {},
        },
      },
      mockResolvers: {},
      mapStoryArgs: ({queryData}) => ({
        repository: queryData.repositoryLabelsQuery.repository!,
      }),
    },
  },
} satisfies RelayStoryObj<typeof RepositoryLabelsInternal, RepositoryLabelsQueries>
