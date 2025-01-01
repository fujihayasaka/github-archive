import type {Meta} from '@storybook/react'
import {PersonalizationSetting as PersonalizationSettingItem} from './PersonalizationSetting'

const meta: Meta = {
  title: 'Recipes/AppearanceSettings/PersonalizationSetting',
  component: PersonalizationSettingItem,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

export const PersonalizationSetting = {
  render: () => <PersonalizationSettingItem />,
}
