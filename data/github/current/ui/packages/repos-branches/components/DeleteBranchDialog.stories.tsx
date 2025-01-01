import type {Meta, StoryObj} from '@storybook/react'
import {getBranches, getPullRequest} from '../test-utils/mock-data'
import {DeleteBranchDialog} from './DeleteBranchDialog'
import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'

const pullRequest = getPullRequest()

const meta: Meta<typeof DeleteBranchDialog> = {
  title: 'Repo Branches/Components/DeleteBranchDialog',
  component: DeleteBranchDialog,
  argTypes: {
    setShowModal: () => {},
    setDeleting: () => {},
  },
  args: {
    branchName: getBranches()[0]!.name,
    pullRequest,
  },
  parameters: {
    a11y: disableA11yRuleForDialog,
  },
}

export const Default: StoryObj<typeof DeleteBranchDialog> = {
  render: args => {
    return <DeleteBranchDialog {...args} showModal />
  },
}

export default meta
