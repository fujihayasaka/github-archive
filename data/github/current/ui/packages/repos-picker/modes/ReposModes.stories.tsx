import {storyWrapper} from '@github-ui/react-core/test-utils'
import {RepoIcon} from '@primer/octicons-react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {Selection} from '../Selection'
import {handlers} from '../test-utils/mock-data'
import type {PickerRepository} from '../types'
import {modes} from './ReposModes'

const meta = {
  title: 'Recipes/ReposPicker/Repos Selection Modes',
  component: Selection,
  decorators: [storyWrapper()],
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof Selection>

export default meta

export const Default = () => {
  const [mode, setMode] = useState('all')
  const [selected, setSelected] = useState<PickerRepository[]>([])
  const [filter, setFilter] = useState('')

  return (
    <div>
      <Selection
        title="Repository access"
        description="Choose which repositories are allowed to create repository-level self-hosted runners."
        selectedMode={mode}
        selectorIcon={RepoIcon}
        onModeChange={setMode}
        modes={[
          modes.all,
          modes.buildMultiple({
            selected,
            onSubmit: setSelected,
          }),
          modes.buildFilter({
            query: filter,
            onSubmit: setFilter,
          }),
        ]}
      />
      <p className="m-3">
        You have selected &apos;{mode}&apos;
        {mode === 'multiple'
          ? ` with ${selected.length} repos`
          : mode === 'filter'
            ? ` with repos matching '${filter}'`
            : ''}
      </p>
    </div>
  )
}

export const All = () => (
  <Selection title="Title" description="Description" selectedMode={modes.all.name} modes={[modes.all]} />
)

export const Multiple = () => {
  const multipleMode = modes.buildMultiple({onSubmit: () => {}})
  return <Selection title="Title" description="Description" selectedMode={multipleMode.name} modes={[multipleMode]} />
}

export const Filter = () => {
  const filterMode = modes.buildFilter({onSubmit: () => {}})
  return <Selection title="Title" description="Description" selectedMode={filterMode.name} modes={[filterMode]} />
}
