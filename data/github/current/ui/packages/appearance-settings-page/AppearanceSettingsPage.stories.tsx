import type {Meta} from '@storybook/react'
import {AppearanceSettingsPage} from './AppearanceSettingsPage'

const meta: Meta = {
  title: 'Recipes/AppearanceSettingsPage',
  component: AppearanceSettingsPage,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

export const Default = {
  name: 'Default',
  render: () => <AppearanceSettingsPage />,
}
