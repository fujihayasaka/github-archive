import type {Meta} from '@storybook/react'
import {ThemeSetting as ThemeSettingItem} from './ThemeSetting'

const meta: Meta = {
  title: 'Recipes/AppearanceSettings/ThemeSetting',
  component: ThemeSettingItem,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

export const ThemeSetting = {
  render: () => <ThemeSettingItem />,
}
