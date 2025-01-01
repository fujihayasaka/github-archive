import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {BranchNextStepDesktop, type BranchNextStepDesktopProps} from './BranchNextStepDesktop'
import {BranchNextStepFlashes} from './BranchNextStepFlashes'
import {Title, Controls} from '@storybook/blocks'

export default {
  title: 'Security Campaigns Shared/Branch Next Step Desktop',
  component: BranchNextStepDesktop,
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
} satisfies Meta<typeof BranchNextStepDesktop>

const defaultArgs = {
  onClose: () => {},
}

export const BranchNextStepDesktopDefault = {
  args: defaultArgs,
  render: (args: BranchNextStepDesktopProps) => <BranchNextStepDesktop {...args} />,
}

export const BranchNextStepDesktopWithFlashes = {
  args: {
    ...defaultArgs,
    flashes: <BranchNextStepFlashes errorMessages={['Something went wrong']} />,
  },
  render: (args: BranchNextStepDesktopProps) => <BranchNextStepDesktop {...args} />,
}
