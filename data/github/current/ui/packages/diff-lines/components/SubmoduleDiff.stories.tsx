import type {Meta, StoryObj} from '@storybook/react'

import {SubmoduleDiff} from './SubmoduleDiff'
import {mockSubmodule, mockSubmoduleWithoutSummaries} from '../test-utils/mock-data'

const meta: Meta<typeof SubmoduleDiff> = {
  title: 'Diff Lines/Submodule Diff',
  component: SubmoduleDiff,
}

type Story = StoryObj<typeof SubmoduleDiff>

export const ModifiedWithSummaries: Story = {
  render: () => <SubmoduleDiff submodule={mockSubmodule} />,
}

export const ModifiedWithoutSummaries: Story = {
  render: () => <SubmoduleDiff submodule={mockSubmoduleWithoutSummaries} />,
}

export const NotLinkable: Story = {
  render: () => <SubmoduleDiff submodule={{...mockSubmodule, submoduleUrl: undefined, contentsUrl: undefined}} />,
}

export const Added: Story = {
  render: () => (
    <SubmoduleDiff submodule={{...mockSubmoduleWithoutSummaries, status: 'ADDED', oldCommitOid: undefined}} />
  ),
}

export const Deleted: Story = {
  render: () => (
    <SubmoduleDiff submodule={{...mockSubmoduleWithoutSummaries, status: 'DELETED', newCommitOid: undefined}} />
  ),
}

export default meta
