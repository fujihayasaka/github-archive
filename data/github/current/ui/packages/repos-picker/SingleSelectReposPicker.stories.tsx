import {noop} from '@github-ui/noop'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {Link} from '@primer/react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {SingleSelectReposPicker} from './SingleSelectReposPicker'
import {handlers} from './test-utils/mock-data'
import {sampleRepos} from './test-utils/test-helpers'
import type {PickerRepository} from './types'

const meta = {
  title: 'Recipes/ReposPicker/Single-select',
  component: SingleSelectReposPicker,
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
} satisfies Meta<typeof SingleSelectReposPicker>

export default meta

export const Default = {}

export const NumerousRepos = {
  parameters: {
    msw: {
      handlers: handlers.numerousRepos,
    },
  },
}

export const WithInitialValue = {
  args: {
    selected: sampleRepos[1],
  },
}

export const Stateful = () => {
  const [selectedItem, setSelectedItem] = useState<PickerRepository | undefined>(undefined)

  const oneClickRepo = sampleRepos[1]!

  return (
    <>
      <SingleSelectReposPicker orgLogin="acme" selected={selectedItem} onSubmit={setSelectedItem} />
      <Link
        className="d-block m-2"
        href="#"
        onClick={e => {
          setSelectedItem(oneClickRepo)
          e.preventDefault()
        }}
      >
        Select {oneClickRepo.name}
      </Link>
    </>
  )
}
