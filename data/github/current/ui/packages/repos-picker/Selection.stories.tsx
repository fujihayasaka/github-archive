import {storyWrapper} from '@github-ui/react-core/test-utils'
import {RepoIcon} from '@primer/octicons-react'
import {Checkbox, TextInput} from '@primer/react'
import type {Meta} from '@storybook/react'
import {useState} from 'react'

import {Selection} from './Selection'

const meta = {
  title: 'Recipes/ReposPicker/Selection',
  component: Selection,
  decorators: [storyWrapper()],
} satisfies Meta<typeof Selection>

export default meta

export const Default = () => {
  const [mode, setMode] = useState('all')
  const [text, setText] = useState('')
  const [checked, setChecked] = useState(false)

  return (
    <div>
      <Selection
        title="Title"
        description="Description"
        selectedMode={mode}
        onModeChange={setMode}
        modes={[
          {name: 'all', label: 'All', description: 'Apply to all'},
          {
            name: 'text',
            label: 'Text',
            description: 'Write something',
            renderEditor: () => (
              <TextInput aria-label="Something" value={text} onChange={e => setText(e.target.value)} />
            ),
          },
          {
            name: 'check',
            label: 'Check',
            description: 'True or false',
            renderEditor: () => <Checkbox checked={checked} onChange={() => setChecked(!checked)} />,
          },
        ]}
      />
      <p className="m-3">
        You have selected &apos;{mode}&apos;
        {mode === 'text' ? ` with '${text}'` : mode === 'check' ? ` with ${checked}` : ''}
      </p>
    </div>
  )
}

export const SingleMode = () => (
  <Selection
    title="Repository access"
    description="Choose which repositories are allowed to create repository-level self-hosted runners."
    selectorIcon={RepoIcon}
    modes={[
      {
        name: 'text',
        label: 'Text',
        description: 'Write something',
        renderEditor: () => <TextInput aria-label="Something" />,
      },
    ]}
  />
)
