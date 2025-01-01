import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {handlers} from '../test-utils/mock-data'
import {MatchingRepositoriesCount} from './MatchingRepositoriesCount'

const meta = {
  title: 'Recipes/ReposPicker/Components/MatchingRepositoriesCount',
  component: MatchingRepositoriesCount,
  decorators: [storyWrapper()],
  args: {
    query: 'test',
    scope: {type: 'organization', slug: 'github'},
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof MatchingRepositoriesCount>

export default meta

export const Default = {}
export const Loading = {
  parameters: {
    msw: {
      handlers: handlers.loading,
    },
  },
}
export const Link = {
  args: {
    href: 'https://github.com',
  },
}
export const NoQuery = {
  args: {
    query: '',
  },
}
