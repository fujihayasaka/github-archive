import type {Meta} from '@storybook/react'
import {AppearanceSettingsNavButton as Button} from './AppearanceSettingsNavButton'

const meta: Meta = {
  title: 'Recipes/AppearanceSettings/AppearanceSettingsNavButton',
  component: Button,
  parameters: {
    controls: {expanded: true, sort: 'requiredFirst'},
  },
}

export default meta

export const AppearanceSettingsNavButton = {
  render: () => (
    <div style={{height: '100px', backgroundColor: 'black', padding: '1rem'}}>
      <Button />
    </div>
  ),
}
