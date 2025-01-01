import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {Link} from '@primer/react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {MultiSelectReposPicker} from './MultiSelectReposPicker'
import {handlers} from './test-utils/mock-data'
import {buildRepo, sampleRepos} from './test-utils/test-helpers'
import type {PickerRepository} from './types'

const meta = {
  title: 'Recipes/ReposPicker/Multi-select',
  component: MultiSelectReposPicker,
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
} satisfies Meta<typeof MultiSelectReposPicker>

export default meta

export const Default = {}

export const NumerousRepos = {
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}

export const NumerousSelected = {
  args: {
    selected: Array.from({length: 2345}, (_, i) => buildRepo(`repo-${i + 1}`, i + 100)),
  },
}

export const Stateful = () => {
  const [selectedItems, setSelectedItems] = useState<PickerRepository[]>([])

  const fruitRepos = sampleRepos.filter(repo => repo.name.includes('fruit'))

  return (
    <>
      <MultiSelectReposPicker orgLogin="acme" selected={selectedItems} onSubmit={setSelectedItems} />
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
