import type {Meta} from '@storybook/react'
import {Accordion} from './Accordion'
import DefaultExample from './examples/DefaultExample'
import SecretScanningFAQ from './examples/SecretScanningFAQ'

const meta = {
  title: 'Recipes/Accordion',
  component: Accordion,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof Accordion>

export default meta

export const Default = {
  name: 'Default',
  render: () => <DefaultExample />,
}

export const SecretScanningFAQExample = {
  name: 'Secret Scanning FAQ',
  render: () => <SecretScanningFAQ />,
}
