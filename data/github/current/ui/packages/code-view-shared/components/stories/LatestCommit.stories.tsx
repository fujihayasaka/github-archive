import type {Meta, StoryObj} from '@storybook/react'

import {storyWrapper} from '@github-ui/react-core/test-utils'
import {LatestCommitSingleLine} from '../LatestCommit'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/LatestCommit',
  component: LatestCommitSingleLine,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {commitCount: '1'},
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof LatestCommitSingleLine>

export default meta

type Story = StoryObj<typeof LatestCommitSingleLine>

export const Default: Story = {}
