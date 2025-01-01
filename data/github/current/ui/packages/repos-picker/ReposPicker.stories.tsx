import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'

import {SingleSelectReposPicker} from './SingleSelectReposPicker'
import {handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/ReposPicker/Common',
  component: SingleSelectReposPicker,
  decorators: [storyWrapper()],
  args: {
    scope: {type: 'organization', slug: 'acme'},
    onSubmit: noop,
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof SingleSelectReposPicker>

export default meta

export const Error = {
  parameters: {
    msw: {
      handlers: handlers.error,
    },
  },
}

export const Loading = {
  parameters: {
    msw: {
      handlers: handlers.loading,
    },
  },
}

export const TwoPickers = () => (
  <>
    <SingleSelectReposPicker scope={{type: 'organization', slug: 'acme'}} onSubmit={noop} />
    <br />
    <SingleSelectReposPicker scope={{type: 'organization', slug: 'acme'}} onSubmit={noop} />
  </>
)
