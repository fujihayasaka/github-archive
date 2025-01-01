import type {Meta, StoryObj} from '@storybook/react'

import type {SafeHTMLString} from '@github-ui/safe-html'
import {DirectoryRichtextContent} from '../DirectoryRichtextContent'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {currentRepositoryDecorator, filesPageInfoDecorator} from '../../../__tests__/story-helpers'

const meta = {
  title: 'Apps/Code View Shared/DirectoryRichtextContent',
  component: DirectoryRichtextContent,
  decorators: [currentRepositoryDecorator, filesPageInfoDecorator, storyWrapper({appPayload: {helpUrl: ''}})],
  args: {
    errorMessage: undefined,
    onAnchorClick: () => {},
    richText: 'This is a test' as SafeHTMLString,
    stickyHeaderHeight: 0,
    path: '/test/path',
    timedOut: false,
  },
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
    jest: {
      timeout: 20_000,
    },
  },
} satisfies Meta<typeof DirectoryRichtextContent>

export default meta

type Story = StoryObj<typeof DirectoryRichtextContent>

export const Default: Story = {}
