import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {useState} from 'react'

import {DynamicReposPicker} from './DynamicReposPicker'
import {handlers} from './test-utils/mock-data'

const meta = {
  title: 'Recipes/ReposPicker/Dynamic',
  component: DynamicReposPicker,
  decorators: [storyWrapper()],
  args: {
    orgLogin: 'acme',
    onSubmit: noop,
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof DynamicReposPicker>

type Story = StoryObj<typeof DynamicReposPicker>

export default meta

export const Default: Story = {}
export const RestrictedProviders: Story = {
  args: {
    allowedProviders: ['custom-properties'],
  },
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
}

export const NumerousRepos: Story = {
  args: {
    query: 'repo-1',
  },
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}

export const Stateful = () => {
  const [q, setQ] = useState('props.environment:prod')

  return <DynamicReposPicker query={q} orgLogin="acme" onSubmit={setQ} />
}
