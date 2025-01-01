import type {Meta, StoryObj} from '@storybook/react'
import {ThemeVisual as ThemeVisualIcon} from './ThemeVisual'

const meta: Meta = {
  title: 'Recipes/AppearanceSettings/ThemeVisual',
  component: ThemeVisualIcon,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

interface ThemeVisualArgs {
  theme?: 'light' | 'dark' | 'dark_dimmed'
}

export const ThemeVisual: StoryObj<typeof ThemeVisualIcon> = {
  render: (args: ThemeVisualArgs) => <ThemeVisualIcon {...args} />,
  args: {
    theme: 'light',
  },
  argTypes: {
    theme: {
      control: 'select',
      options: ['light', 'dark', 'dark_dimmed'],
    },
  },
}
