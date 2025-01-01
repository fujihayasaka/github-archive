import {ControlGroup} from '@github-ui/control-group'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {getRepoFilterProviders} from '@github-ui/repos-filter/providers'
import {RepoIcon} from '@primer/octicons-react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {handlers} from '../test-utils/mock-data'
import type {PickerRepository, PickerScope} from '../types'
import {modes} from './ReposModes'

const meta = {
  title: 'Recipes/ReposPicker/Repos Selection Modes',
  component: ControlGroup.Selector,
  decorators: [storyWrapper()],
  parameters: {
    msw: {
      handlers: handlers.success,
    },
  },
} satisfies Meta<typeof ControlGroup.Selector>

const orgScope: PickerScope = {type: 'organization', slug: 'acme'}
const providers = getRepoFilterProviders(['fork', 'visibility'])

export default meta

const ReposSelectionStory = ({scope}: {scope: PickerScope}) => {
  const [mode, setMode] = useState('all')
  const [selected, setSelected] = useState<PickerRepository[]>([])
  const [filter, setFilter] = useState('')

  return (
    <ControlGroup>
      <ControlGroup.Selector
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
            scope,
          }),
          modes.buildFilter({
            query: filter,
            onSubmit: setFilter,
            providers,
            scope,
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
    </ControlGroup>
  )
}

export const Default = () => <ReposSelectionStory scope={orgScope} />

const enterpriseScope: PickerScope = {type: 'enterprise', slug: 'acme-corp'}
export const Enterprise = () => <ReposSelectionStory scope={enterpriseScope} />

const userScope: PickerScope = {type: 'user', slug: 'octocat'}
export const User = () => <ReposSelectionStory scope={userScope} />

export const CustomNames = () => {
  const [mode, setMode] = useState('my-all')

  return (
    <ControlGroup>
      <ControlGroup.Selector
        title="Custom names"
        description="Consumers can override the built-in mode names."
        selectedMode={mode}
        onModeChange={setMode}
        modes={[
          {...modes.all, name: 'my-all'},
          modes.buildMultiple({name: 'my-multiple', onSubmit: () => {}, scope: orgScope}),
          modes.buildFilter({name: 'my-filter', onSubmit: () => {}, scope: orgScope, providers}),
        ]}
      />
      <p className="m-3">You have selected &apos;{mode}&apos;</p>
    </ControlGroup>
  )
}

export const All = () => (
  <ControlGroup>
    <ControlGroup.Selector title="Title" description="Description" selectedMode={modes.all.name} modes={[modes.all]} />
  </ControlGroup>
)

export const Multiple = () => {
  const multipleMode = modes.buildMultiple({onSubmit: () => {}, scope: orgScope})
  return (
    <ControlGroup>
      <ControlGroup.Selector
        title="Title"
        description="Description"
        selectedMode={multipleMode.name}
        modes={[multipleMode]}
      />
    </ControlGroup>
  )
}

export const Filter = () => {
  const filterMode = modes.buildFilter({onSubmit: () => {}, scope: orgScope, providers})
  return (
    <ControlGroup>
      <ControlGroup.Selector
        title="Title"
        description="Description"
        selectedMode={filterMode.name}
        modes={[filterMode]}
      />
    </ControlGroup>
  )
}
