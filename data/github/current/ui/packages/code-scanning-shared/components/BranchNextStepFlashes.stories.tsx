import type {Meta} from '@storybook/react'
import {BranchNextStepFlashes, type BranchNextStepFlashesProps} from './BranchNextStepFlashes'

export default {
  title: 'Security Campaigns Shared/Branch Next Step Flashes',
  component: BranchNextStepFlashes,
  argTypes: {},
} as Meta

const defaultArgs = {
  errorMessages: ['Something went wrong'],
}

export const BranchNextStepFlashesDefault = {
  args: defaultArgs,
  render: (args: BranchNextStepFlashesProps) => <BranchNextStepFlashes {...args} />,
}
