import type {Meta} from '@storybook/react'
import {HiddenUnicodeAlert} from './HiddenUnicodeAlert'

const meta = {
  title: 'Recipes/HiddenUnicodeBanner',
  component: HiddenUnicodeAlert,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof HiddenUnicodeAlert>

export default meta

export const HiddenUnicodeAlertExample = {
  render: () => (
    <div className="m-6 p-6">
      <HiddenUnicodeAlert />
    </div>
  ),
}
