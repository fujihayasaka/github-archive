import {storyWrapper} from '@github-ui/react-core/test-utils'
import {Checkbox, TextInput} from '@primer/react'
import {useState} from 'react'
import {ControlGroup} from '../ControlGroup'
import {RocketIcon} from '@primer/octicons-react'

const meta = {
  title: 'Recipes/ControlGroup/ControlGroup.Selector',
  component: ControlGroup,
  decorators: [storyWrapper()],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
}

export default meta

export const Default = () => {
  const [mode, setMode] = useState('all')
  const [text, setText] = useState('')
  const [checked, setChecked] = useState(false)

  return (
    <div>
      <ControlGroup>
        <ControlGroup.Selector
          title="Title"
          description="Description"
          selectedMode={mode}
          onModeChange={setMode}
          selectorIcon={RocketIcon}
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
      </ControlGroup>
      <p className="m-3">
        You have selected &apos;{mode}&apos;
        {mode === 'text' ? ` with '${text}'` : mode === 'check' ? ` with ${checked}` : ''}
      </p>
    </div>
  )
}

export const SingleMode = () => (
  <ControlGroup>
    <ControlGroup.Selector
      title="Title"
      description="Description"
      modes={[
        {
          name: 'text',
          label: 'Text',
          description: 'Write something',
          renderEditor: () => <TextInput aria-label="Something" />,
        },
      ]}
    />
  </ControlGroup>
)
