import {VisualStudioMatchDialog} from './VisualStudioMatchDialog'
import type {Meta, StoryObj} from '@storybook/react'

const meta: Meta<typeof VisualStudioMatchDialog> = {
  title: 'Apps/Licensing/Enterprise Cloud/VisualStudioMatchDialog',
  component: VisualStudioMatchDialog,
  args: {
    errorMessage: null,
    hasVssLicensesLeft: true,
    isSaving: false,
    isVolumeLicensed: false,
    licenseeFullName: 'Madelyn Curtis',
    licenseeLogin: 'mcurtis',
  },
}
export default meta

type Story = StoryObj<typeof VisualStudioMatchDialog>

export const Metered: Story = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  render: function DefaultStory(args) {
    return <VisualStudioMatchDialog {...args} isVolumeLicensed={false} />
  },
}

export const Volume: Story = {
  render: function ExcludingPerSeatCostStory(args) {
    return <VisualStudioMatchDialog {...args} isVolumeLicensed />
  },
}

export const Error: Story = {
  render: function ErrorStory(args) {
    return <VisualStudioMatchDialog {...args} errorMessage="An error occurred" />
  },
}

export const NoVssLicensesLeft: Story = {
  render: function NoVssLicensesLeftStory(args) {
    return <VisualStudioMatchDialog {...args} hasVssLicensesLeft={false} />
  },
}
