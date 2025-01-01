import type {Meta, StoryObj} from '@storybook/react'
import {AppearanceSettingsPane} from '../AppearanceSettings'

const meta = {
  title: 'Recipes/AppearanceSettings',
  component: AppearanceSettingsPane,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
} satisfies Meta<typeof AppearanceSettingsPane>

export default meta

export const Example: StoryObj = {
  render: () => <AppearanceSettingsPane />,
}
Example.storyName = 'AppearanceSettings'
