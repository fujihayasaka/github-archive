import {MemoryRouter} from 'react-router-dom'
import type {Meta} from '@storybook/react'
import {DiffViewSettings, type DiffViewSettingsProps} from './DiffViewSettings'

const meta = {
  title: 'Recipes/DiffViewSettings',
  component: DiffViewSettings,
  decorators: [
    Story => (
      <MemoryRouter future={{v7_relativeSplatPath: true, v7_startTransition: true}}>
        <Story />
      </MemoryRouter>
    ),
  ],
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof DiffViewSettings>

export default meta

const defaultArgs: DiffViewSettingsProps = {
  lineSpacingPreferenceAvailable: true,
  reloadOnChange: false,
}

export const Default = {
  args: defaultArgs,
  render: (args: DiffViewSettingsProps) => <DiffViewSettings {...args} />,
}
