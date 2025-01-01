import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {Link} from '@primer/react'
import type {Meta, StoryObj} from '@storybook/react'
import {useState} from 'react'

import {MultiSelectReposPicker} from './MultiSelectReposPicker'
import {handlers} from './test-utils/mock-data'
import {type BillingRepo, buildRepo, sampleRepos} from './test-utils/test-helpers'
import type {PickerRepository} from './types'

const meta = {
  title: 'Recipes/ReposPicker/Multi-select',
  component: MultiSelectReposPicker,
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
} satisfies Meta<typeof MultiSelectReposPicker>

export default meta

type Story = StoryObj<typeof MultiSelectReposPicker>

export const Default: Story = {}

export const Enterprise: Story = {
  args: {
    scope: {type: 'enterprise', slug: 'acme-corp'},
  },
}

export const NumerousRepos: Story = {
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}

export const NumerousSelected: Story = {
  args: {
    selected: Array.from({length: 2345}, (_, i) => buildRepo(`repo-${i + 1}`, i + 100)),
  },
}

export const ScopedVisibility: Story = {
  args: {
    scope: {type: 'organization', slug: 'acme', visibility: ['private', 'internal']},
  },
}

export const Stateful = () => {
  const [selectedItems, setSelectedItems] = useState<PickerRepository[]>([])

  const fruitRepos = sampleRepos.filter(repo => repo.name.includes('fruit'))

  return (
    <>
      <MultiSelectReposPicker
        scope={{type: 'organization', slug: 'acme'}}
        selected={selectedItems}
        onSubmit={setSelectedItems}
      />
      <Link
        className="d-block m-2"
        href="#"
        onClick={e => {
          setSelectedItems(fruitRepos)
          e.preventDefault()
        }}
      >
        Select all fruits repos
      </Link>
    </>
  )
}

export const CustomRepoItemStateful = () => {
  const [selectedItems, setSelectedItems] = useState<BillingRepo[]>([])
  const [temporaryItems, setTemporaryItems] = useState<BillingRepo[]>(selectedItems)
  const seats = temporaryItems.reduce((acc, repo) => acc + (repo.seats ?? 0), 0)

  return (
    <MultiSelectReposPicker
      scope={{type: 'organization', slug: 'acme'}}
      selected={selectedItems}
      onChange={setTemporaryItems}
      onSubmit={setSelectedItems}
      getSearchUrl={query => `/billing/repos-search?q=${query}`}
      onRenderFooterDetails={() => (
        <div className="flex-1 text-mono">{`${temporaryItems.length} repos with ${seats} seats`}</div>
      )}
    />
  )
}
CustomRepoItemStateful.parameters = {
  msw: {
    handlers: handlers.successForBilling,
  },
}

export const CustomRepoItem: Story = {
  args: {
    getSearchUrl: query => `/billing/repos-search?q=${query}`,
    onRenderFooterDetails: () => <div className="flex-1 text-mono">&lt;custom footer&gt;</div>,
  },
  parameters: {
    msw: {
      handlers: handlers.successForBilling,
    },
  },
}
