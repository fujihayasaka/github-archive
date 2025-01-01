import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {BranchNextStepLocal, type BranchNextStepLocalProps} from './BranchNextStepLocal'
import {BranchNextStepFlashes} from './BranchNextStepFlashes'
import {Title, Controls} from '@storybook/blocks'

export default {
  title: 'Security Campaigns Shared/Branch Next Step Local',
  component: BranchNextStepLocal,
  argTypes: {},
  parameters: {
    a11y: disableA11yRuleForDialog,
    docs: {
      page: () => (
        <>
          <Title />
          <Controls />
        </>
      ),
    },
  },
} satisfies Meta<typeof BranchNextStepLocal>

const defaultArgs = {
  branch: 'test-branch',
  onClose: () => {},
}

export const BranchNextStepLocalDefault = {
  args: defaultArgs,
  render: (args: BranchNextStepLocalProps) => <BranchNextStepLocal {...args} />,
}

export const BranchNextStepLocalWithFlashes = {
  args: {
    ...defaultArgs,
    flashes: <BranchNextStepFlashes errorMessages={['Something went wrong']} />,
  },
  render: (args: BranchNextStepLocalProps) => <BranchNextStepLocal {...args} />,
}
